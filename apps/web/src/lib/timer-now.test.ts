import { describe, expect, it } from "vitest";

import type { ClassTimerPayload } from "@/api/class-timers";
import type { TimerSegment } from "@/api/executions";
import type { WorkoutBody } from "@/api/workouts";
import type { PlanRow, PlanSection } from "@/lib/structured-plan/types";
import type { IntervalWindow } from "@/lib/timer-engine";

import { compressValues, timerNow, windowRound, type TimerNow } from "./timer-now";

let uid = 0;
const ex = (name: string, dose = "", more: Partial<PlanRow> = {}): PlanRow => ({
  id: `r${uid++}`,
  kind: "ex",
  name,
  dose,
  load: "",
  cells: [],
  ...more,
});
const plan = (flow: PlanSection["flow"], params: PlanSection["params"], blocks: PlanRow[][], more: Partial<PlanSection> = {}): PlanSection => ({
  v: 1,
  flow,
  params,
  blocks,
  score: "",
  ...more,
});

const segment = (more: Partial<TimerSegment> = {}): TimerSegment => ({
  segment_key: "s",
  section_id: "sec-1",
  section_name: "Engine",
  format: "structured_plan",
  kind: "countup",
  duration_seconds: null,
  round: null,
  total_rounds: null,
  label: "",
  scoreable: false,
  score_config: null,
  exercises: [],
  ...more,
});
const window = (index: number, count: number | null = null): IntervalWindow => ({ index, count, elapsedMs: 0, lengthMs: 60_000 });

function payload(body: WorkoutBody | null, freeText: string | null = null): Pick<ClassTimerPayload, "workout"> {
  return { workout: { id: "w", title: "WOD", authoring_mode: null, free_text_body: freeText, body } };
}
const planBody = (section: PlanSection, id = "sec-1"): WorkoutBody => ({ kind: "plan", sections: [{ id, name: "Engine", plan: section }] });

/** "dose name @ load" per line of each block, "[" / "]" around a group. */
const brief = (now: TimerNow | null) =>
  now?.blocks.map((block) =>
    block.text ??
    block.lines.map(
      (line) =>
        `${line.group?.first ? "[" : ""}${[line.dose, line.name].filter(Boolean).join(" ")}${line.load ? ` @ ${line.load}` : ""}${line.group?.last ? "]" : ""}`,
    ),
  );

describe("timerNow: structured plan", () => {
  it("shows this EMOM minute's exercises, alternating blocks by minute", () => {
    const section = plan("emom", { every: "1:00", times: "10" }, [[ex("Burpee", "10")], [ex("Air squat", "20"), ex("Push-up", "10")]]);
    const body = payload(planBody(section));
    const seg = segment({ kind: "interval_cycle", duration_seconds: 60, total_rounds: 10, timer_config: { plan_flow: "emom" } });

    const minute1 = timerNow(body, { segment: seg, clock: { window: window(1, 10) } as never });
    const minute2 = timerNow(body, { segment: seg, clock: { window: window(2, 10) } as never });

    expect(minute1?.scope).toBe("step");
    expect(brief(minute1)).toEqual([["10 Burpee"]]);
    expect(brief(minute2)).toEqual([["20 Air squat", "10 Push-up"]]);
    expect(brief(timerNow(body, { segment: seg, clock: { window: window(3, 10) } as never }))).toEqual([["10 Burpee"]]);
  });

  it("keeps cycling an open EMOM past its generated slots", () => {
    const section = plan("emom", { every: "1:00" }, [[ex("Thruster", "5")], [ex("Pull-up", "5")]]);
    const seg = segment({ kind: "interval_cycle", duration_seconds: 60, timer_config: { plan_flow: "emom" } });
    expect(brief(timerNow(payload(planBody(section)), { segment: seg, clock: { window: window(62) } as never }))).toEqual([["5 Pull-up"]]);
  });

  it("maps intervals' work and off windows to rounds and shows the next round while resting", () => {
    const section = plan("intervals", { work: "20″", off: "10″", rounds: "8" }, [[ex("Row", "max cal")], [ex("Bike", "max cal")]]);
    const seg = segment({
      kind: "interval_cycle",
      duration_seconds: 20,
      total_rounds: 15,
      timer_config: { plan_flow: "intervals", interval_pattern_seconds: [20, 10] },
    });
    const body = payload(planBody(section));

    expect(windowRound(seg, window(3, 15))).toEqual({ round: 2, rounds: 8, rest: false });
    expect(windowRound(seg, window(4, 15))).toEqual({ round: 2, rounds: 8, rest: true });
    expect(brief(timerNow(body, { segment: seg, clock: { window: window(3, 15) } as never }))).toEqual([["max cal Bike"]]);

    const resting = timerNow(body, { segment: seg, clock: { window: window(2, 15) } as never });
    expect(resting?.upcoming).toBe(true);
    expect(brief(resting)).toEqual([["max cal Bike"]]);
  });

  it("shows one AMRAP round with a superset done together", () => {
    const a = ex("Pull-up", "5", { group: "g" });
    const b = ex("Push-up", "10", { group: "g" });
    const section = plan("amrap", { dur: "12" }, [[a, b, ex("Air squat", "15")]], { structs: { g: { kind: "superset" } } });
    const now = timerNow(payload(planBody(section)), { segment: segment({ kind: "countdown" }), clock: null });

    expect(now?.scope).toBe("round");
    expect(brief(now)).toEqual([["[5 Pull-up", "10 Push-up]", "15 Air squat"]]);
  });

  it("shows a For Time section with its rep scheme across rounds", () => {
    const section = plan("for_time", { rounds: "1", cap: "15" }, [[ex("Thruster", "21-15-9", { load: "43kg" }), ex("Pull-up", "21-15-9")]]);
    const now = timerNow(payload(planBody(section)), { segment: segment(), clock: null });

    expect(now?.scope).toBe("section");
    expect(brief(now)).toEqual([["21-15-9 Thruster @ 43 kg", "21-15-9 Pull-up"]]);
  });

  it("shows the interruption rows with how often they come", () => {
    const section = plan("amrap", { dur: "20", intEvery: "4:00" }, [[ex("Run", "200 m")]], {
      mods: { interrupt: true },
      interrupt: [ex("Burpee", "10")],
    });
    const now = timerNow(payload(planBody(section)), { segment: segment({ kind: "countdown" }), clock: null });
    expect(now?.blocks[1]).toMatchObject({ everySecs: 240, lines: [{ name: "Burpee", dose: "10" }] });
  });
});

describe("timerNow: other ways a WOD is written", () => {
  it("shows a structured segment's exercises for its window", () => {
    const seg = segment({
      format: "emom",
      kind: "interval_cycle",
      duration_seconds: 60,
      timer_config: { interval_pattern_seconds: [60, 60] },
      exercises: [
        { id: "a", name: "Clean", prescription_value: 3, prescription_unit: "reps", load_value: 70, load_mode: "pct_1rm", interval_assignment: 1 },
        { id: "b", name: "Toes to bar", prescription_value: 12, prescription_unit: "reps", interval_assignment: 2 },
        { id: "h", name: "Header", item_type: "header" },
      ],
    });
    const now = timerNow(payload(null), { segment: seg, clock: { window: window(2) } as never });
    expect(now?.scope).toBe("step");
    expect(brief(now)).toEqual([["12 Toes to bar"]]);
    expect(brief(timerNow(payload(null), { segment: seg, clock: { window: window(1) } as never }))).toEqual([["3 Clean @ 70%"]]);
  });

  it("shows the text section the clock runs", () => {
    const body: WorkoutBody = {
      kind: "text_sections",
      sections: [
        { id: "t1", title: "Strength", text: "5x5 back squat", document: null, timer: null, scoring: [] },
        { id: "t2", title: "Metcon", text: "AMRAP 12\n10 burpees", document: null, timer: null, scoring: [] },
      ],
    };
    const now = timerNow(payload(body), { segment: segment({ section_id: "t2", format: "amrap" }), clock: null });
    expect(now).toMatchObject({ scope: "section", blocks: [{ title: "Metcon", text: "AMRAP 12\n10 burpees" }] });
  });

  it("shows the whole free-text WOD", () => {
    const now = timerNow(payload(null, "  21-15-9\nThrusters\nPull-ups "), { segment: segment({ section_id: "free-text" }), clock: null });
    expect(now).toMatchObject({ scope: "workout", blocks: [{ text: "21-15-9\nThrusters\nPull-ups" }] });
  });

  it("shows the whole WOD under a timer the coach picked for the class", () => {
    const section = plan("sets", { sets: "3", rest: "90″" }, [[ex("Bench press", "", { cells: [{ d: "8", l: "60kg" }, { d: "6", l: "65kg" }, { d: "4", l: "70kg" }] })]]);
    const now = timerNow(payload(planBody(section)), { segment: segment({ section_id: "free-text", format: "emom" }), clock: null });
    expect(now?.scope).toBe("workout");
    expect(brief(now)).toEqual([["8-6-4 Bench press @ 60-65-70 kg"]]);
  });

  it("shows nothing for a workout with nothing written", () => {
    expect(timerNow(payload(null), { segment: segment(), clock: null })).toBeNull();
    expect(timerNow({ workout: null }, null)).toBeNull();
  });
});

describe("compressValues", () => {
  it("keeps one value, joins rep schemes and shares a unit", () => {
    expect(compressValues(["12", "12", "12"])).toBe("12");
    expect(compressValues(["21", "15", "9"])).toBe("21-15-9");
    expect(compressValues(["60 kg", "65 kg", "65 kg", "70 kg"])).toBe("60-65-70 kg");
    expect(compressValues(["400 m", "max cal"])).toBe("400 m / max cal");
    expect(compressValues(["", ""])).toBe("");
  });
});
