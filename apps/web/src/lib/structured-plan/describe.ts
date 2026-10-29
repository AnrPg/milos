/**
 * ADR-270: a section in words (for the editor's time step and the WOD view),
 * its clock as timeline segments, and a one-line summary for closed section
 * cards. Words are i18n keys under `PlanCore.describe.*` and
 * `PlanCore.summary.*`; values are already formatted (clocks, counts).
 */
import { clock, parseClock, parseTimes, type PlanText } from "./parse";
import { paramCount, paramSecs } from "./rounds";
import type { PlanRow, PlanSection } from "./types";

/**
 * The section as one sentence of parts, joined with a space by the UI:
 * e.g. `describe.emom` {every: "2:30", times: 4, total: "10:00"} then
 * `describe.interrupt` {every: "2:00"}. Typed values (rest, cap) are kept
 * as typed.
 */
export function describe(section: PlanSection): PlanText[] {
  const p = section.params;
  const out: PlanText[] = [];
  switch (section.flow) {
    case "emom": {
      const e = paramSecs(section, "every");
      const n = paramCount(section, "times");
      if (e) {
        out.push(
          n
            ? { key: "PlanCore.describe.emom", values: { every: clock(e), times: n, total: clock(e * n) } }
            : { key: "PlanCore.describe.emomOpen", values: { every: clock(e) } },
        );
      }
      break;
    }
    case "amrap": {
      const w = parseTimes(p.dur || "", "min");
      if (w && w !== "bad") {
        if (w.secs.length > 1) {
          const values = { count: w.secs.length, list: w.secs.map(clock).join(", ") };
          out.push(
            p.rest
              ? { key: "PlanCore.describe.amrapWindowsRest", values: { ...values, rest: p.rest } }
              : { key: "PlanCore.describe.amrapWindows", values },
          );
        } else out.push({ key: "PlanCore.describe.amrap", values: { dur: clock(w.secs[0]) } });
      }
      break;
    }
    case "for_time": {
      const rounds = paramCount(section, "rounds") || 1;
      out.push(p.cap ? { key: "PlanCore.describe.forTimeCap", values: { rounds, cap: p.cap } } : { key: "PlanCore.describe.forTime", values: { rounds } });
      break;
    }
    case "intervals":
      out.push(
        section.mods?.hr
          ? { key: "PlanCore.describe.intervalsHr", values: { rounds: p.rounds || "?", work: p.work || "?", hr: p.hrTarget || "?" } }
          : { key: "PlanCore.describe.intervals", values: { rounds: p.rounds || "?", work: p.work || "?", off: p.off || "?" } },
      );
      break;
    case "sets":
      out.push(p.rest ? { key: "PlanCore.describe.setsRest", values: { sets: p.sets || "?", rest: p.rest } } : { key: "PlanCore.describe.sets", values: { sets: p.sets || "?" } });
      break;
    case "rest":
      if (p.dur) out.push({ key: "PlanCore.describe.rest", values: { dur: p.dur } });
      break;
  }
  if (section.mods?.interrupt) out.push({ key: "PlanCore.describe.interrupt", values: { every: p.intEvery || "?" } });
  return out;
}

/** One stretch of the clock. `slot` = which block (alternating EMOM minutes, interval rounds). */
export type TimelineSegment = { secs: number; kind: "work" | "rest" | "slot"; slot?: number };
/** Segments in order, interruption marks (seconds from the start) and the total length. */
export type Timeline = { segments: TimelineSegment[]; interrupts: number[]; total: number };

/** Length shown for an uncapped For Time with interruptions (display only, as in the mockup). */
const UNCAPPED_DISPLAY_SECS = 12 * 60;

/**
 * The shape of the clock: EMOM slots (alternating blocks), AMRAP windows with
 * rest between, intervals work/rest (HR rest drawn as 60 s), For Time with
 * interruptions as one stretch (its cap). Interruption marks every
 * `intEvery`. Flows without a clock give no segments.
 */
export function timeline(section: PlanSection): Timeline {
  const segs: TimelineSegment[] = [];
  const k = Math.max(1, section.blocks.length);
  if (section.flow === "emom") {
    const e = paramSecs(section, "every");
    const n = paramCount(section, "times") || 10;
    if (e) for (let i = 0; i < n; i++) segs.push({ secs: e, kind: "slot", slot: i % k });
  } else if (section.flow === "amrap") {
    const w = parseTimes(section.params.dur || "", "min");
    const r = section.params.rest ? parseClock(section.params.rest, "smart") : null;
    if (w && w !== "bad") {
      w.secs.forEach((x, i) => {
        if (i && typeof r === "number" && r > 0) segs.push({ secs: r, kind: "rest" });
        segs.push({ secs: x, kind: "work" });
      });
    }
  } else if (section.flow === "intervals") {
    const a = paramSecs(section, "work");
    const b = paramSecs(section, "off") || (section.mods?.hr ? 60 : 0);
    const n = paramCount(section, "rounds");
    if (a && n) {
      for (let i = 0; i < n; i++) {
        segs.push({ secs: a, kind: "slot", slot: i % k });
        if (b > 0) segs.push({ secs: b, kind: "rest" });
      }
    }
  } else if (section.flow === "for_time" && section.mods?.interrupt) {
    segs.push({ secs: paramSecs(section, "cap") || UNCAPPED_DISPLAY_SECS, kind: "work" });
  }
  const total = segs.reduce((a, s) => a + s.secs, 0);
  const interrupts: number[] = [];
  const ie = section.mods?.interrupt ? paramSecs(section, "intEvery") : null;
  if (ie && total) for (let t = ie; t < total; t += ie) interrupts.push(t);
  return { segments: segs, interrupts, total };
}

/** An exercise name in a summary; `perSide` shows "(per side)". */
export type SummaryName = { name: string; perSide: boolean };

/** Rows marked "per side" (the `side` measure). */
export const isPerSide = (row: Pick<PlanRow, "extra">): boolean => Boolean(row.extra?.includes("side"));

/**
 * A closed section in one line: `params` parts (`PlanCore.summary.*`), and
 * the exercise names per block (empty blocks left out), joined " + " within
 * a block and " / " between blocks by the UI.
 */
export function summary(section: PlanSection): { params: PlanText[]; names: SummaryName[][] } {
  const p = section.params;
  const params: PlanText[] = [];
  switch (section.flow) {
    case "emom":
      params.push(p.times ? { key: "PlanCore.summary.emom", values: { every: p.every || "?", times: p.times } } : { key: "PlanCore.summary.emomOpen", values: { every: p.every || "?" } });
      break;
    case "sets":
      params.push({ key: "PlanCore.summary.sets", values: { sets: p.sets || "?" } });
      break;
    case "amrap": {
      const w = parseTimes(p.dur || "", "min");
      if (w && w !== "bad") {
        params.push(w.secs.length > 1 ? { key: "PlanCore.summary.windows", values: { count: w.secs.length } } : { key: "PlanCore.summary.dur", values: { dur: clock(w.secs[0]) } });
      }
      break;
    }
    case "for_time": {
      const n = paramCount(section, "rounds");
      if (n && n > 1) params.push({ key: "PlanCore.summary.rounds", values: { rounds: n } });
      break;
    }
    case "intervals":
      params.push(
        section.mods?.hr && !p.off
          ? { key: "PlanCore.summary.intervalsHr", values: { rounds: p.rounds || "?", work: p.work || "?" } }
          : { key: "PlanCore.summary.intervals", values: { rounds: p.rounds || "?", work: p.work || "?", off: p.off || "?" } },
      );
      break;
    case "rest":
      if (p.dur) params.push({ key: "PlanCore.summary.dur", values: { dur: p.dur } });
      break;
  }
  if (section.mods?.interrupt) params.push({ key: "PlanCore.summary.interrupt", values: { every: p.intEvery || "?" } });
  const names = section.blocks
    .map((b) => b.filter((r) => r.kind === "ex" && r.name.trim()).map((r) => ({ name: r.name.trim(), perSide: isPerSide(r) })))
    .filter((b) => b.length);
  return { params, names };
}
