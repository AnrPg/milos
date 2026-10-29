import { act, fireEvent, render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { PlanRow, PlanSection } from "@/lib/structured-plan/types";

import en from "../../../../../messages/en.json";
import { PlanExecution, type PlanRunLog, type PlanRunResult, type PlanRunSnapshot } from "./PlanExecution";

let uid = 0;
const ex = (name: string, dose: string, more: Partial<PlanRow> = {}): PlanRow => ({ id: `r${uid++}`, kind: "ex", name, dose, load: "", cells: [], ...more });
const section = (flow: PlanSection["flow"], params: PlanSection["params"], blocks: PlanRow[][], more: Partial<PlanSection> = {}): PlanSection => ({
  v: 1,
  flow,
  params,
  blocks,
  score: "none",
  ...more,
});

function renderRun(
  plan: PlanSection,
  onComplete = vi.fn<(r: PlanRunResult) => void>(),
  onLog = vi.fn<(l: PlanRunLog) => void>(),
  more: Partial<React.ComponentProps<typeof PlanExecution>> = {},
) {
  const view = render(
    <NextIntlClientProvider locale="en" messages={en}>
      <PlanExecution section={plan} sectionId="sec-1" sectionName="A" onComplete={onComplete} onLog={onLog} {...more} />
    </NextIntlClientProvider>,
  );
  return { onComplete, onLog, unmount: view.unmount };
}

const advance = (ms: number) => act(() => vi.advanceTimersByTime(ms));
const key = (k: string) => act(() => void fireEvent.keyDown(window, { key: k }));
const heading = () => screen.queryByRole("heading", { level: 2 })?.textContent ?? null;
const timer = () => screen.getByRole("timer").textContent;

describe("PlanExecution", () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it("advances a set-wise superset with the next button and the keyboard", () => {
    renderRun(
      section("sets", { sets: "2", rest: "90″" }, [[
        ex("Bench Press", "", { group: "g", cells: [{ d: "12", l: "60kg" }, { d: "10", l: "+5" }] }),
        ex("DB Fly", "", { group: "g", cells: [{ d: "15", l: "12kg" }] }),
      ]]),
    );
    expect(screen.getByTestId("plan-run")).toBeInTheDocument();
    fireEvent.click(screen.getByTestId("plan-run-next"));
    expect(heading()).toBe("Bench Press");
    expect(screen.getByText("Set 1 of 2")).toBeInTheDocument();
    expect(screen.getByText("Superset 1/2")).toBeInTheDocument();
    expect(screen.getByText("60 kg")).toBeInTheDocument();
    expect(screen.getByText("Up next")).toBeInTheDocument();

    key(" ");
    expect(heading()).toBe("DB Fly");
    key("Enter");
    expect(screen.getByText("Rest 1:30")).toBeInTheDocument();
    key("Backspace");
    expect(heading()).toBe("DB Fly");
    key("Enter");
    advance(90_000);
    expect(heading()).toBe("Bench Press");
    expect(screen.getByText("Set 2 of 2")).toBeInTheDocument();
    expect(screen.getByText("65 kg")).toBeInTheDocument();
  });

  it("interrupts For Time every 2 minutes and resumes the main work", () => {
    renderRun(
      section("for_time", { rounds: "1", intEvery: "2:00" }, [[ex("Thruster", "75")]], { mods: { interrupt: true }, interrupt: [ex("Burpee over Bar", "10")] }),
    );
    key("Enter");
    expect(heading()).toBe("Thruster");
    advance(119_000);
    expect(timer()).toBe("1:59");
    expect(heading()).toBe("Thruster");
    advance(1_000);
    expect(heading()).toBe("Burpee over Bar");
    expect(screen.getByText("Interruption")).toBeInTheDocument();
    expect(screen.getByText("Then back to")).toBeInTheDocument();
    advance(20_000);
    key(" ");
    expect(heading()).toBe("Thruster");
    advance(100_000);
    expect(heading()).toBe("Burpee over Bar");
    expect(timer()).toBe("4:00");
  });

  it("counts EMOM slots down and waits when the athlete is done early", () => {
    renderRun(section("emom", { every: "1:00", times: "2" }, [[ex("Wall Ball", "20")], [ex("Burpee", "12")]]));
    key("Enter");
    expect(timer()).toBe("1:00");
    advance(15_000);
    expect(timer()).toBe("0:45");
    key(" ");
    expect(screen.getByText("Done, rest until the next one")).toBeInTheDocument();
    expect(screen.getByTestId("plan-run-next")).toBeDisabled();
    advance(45_000);
    expect(heading()).toBe("Burpee");
    expect(timer()).toBe("1:00");
  });

  it("ends a heart-rate rest when the athlete taps HR reached", () => {
    renderRun(section("intervals", { work: "0:30", rounds: "2", hrTarget: "120" }, [[ex("Row", "max m")]], { mods: { hr: true } }));
    key("Enter");
    advance(30_000);
    expect(screen.getByText("Rest until your heart rate falls to 120")).toBeInTheDocument();
    advance(40_000);
    expect(screen.getByText("Rest until your heart rate falls to 120")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "HR reached" }));
    expect(heading()).toBe("Row");
    expect(timer()).toBe("0:30");
  });

  it("logs what differs from the target and asks for the score at the end", () => {
    const { onComplete, onLog } = renderRun(
      section("for_time", { rounds: "1" }, [[ex("Thruster", "21", { load: "43kg" }), ex("Pull-up", "21")]], { score: "time" }),
    );
    key("Enter");
    fireEvent.change(screen.getByLabelText("Reps done"), { target: { value: "18" } });
    advance(40_000);
    fireEvent.click(screen.getByTestId("plan-run-next"));
    expect(onLog).toHaveBeenCalledWith(expect.objectContaining({ field: "reps", actual: "18", canonical: "21" }));
    advance(35_000);
    expect(screen.getByTestId("plan-run-next")).toHaveTextContent("Finish");
    fireEvent.click(screen.getByTestId("plan-run-next"));
    expect(screen.getByText("Section done")).toBeInTheDocument();
    const dialog = screen.getByRole("dialog");
    expect(dialog).toHaveTextContent("Time");
    expect(screen.getByDisplayValue("1:15")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    expect(onComplete).toHaveBeenCalledWith({
      score: expect.objectContaining({ section_id: "sec-1", value: "1:15", score_type: "time" }),
      elapsedMs: 75_000,
      actuals: [
        expect.objectContaining({ row_id: expect.any(String), exercise_name: "Thruster", prescribed_reps: 21, actual_reps: 18, prescribed_load_kg: 43, actual_load_kg: 43, logged: true }),
        expect.objectContaining({ exercise_name: "Pull-up", prescribed_reps: 21, actual_reps: 21, logged: false }),
      ],
    });
  });

  it("resumes from a snapshot with the clock still running while the page was away", () => {
    const plan = section("emom", { every: "1:00", times: "3" }, [[ex("Wall Ball", "20")], [ex("Burpee", "12")]]);
    let saved: PlanRunSnapshot | null = null;
    const first = renderRun(plan, undefined, undefined, { onProgress: (s) => (saved = s) });
    key("Enter");
    advance(30_000);
    key(" ");
    expect(saved!.state.status).toBe("running");
    first.unmount();
    advance(40_000);
    renderRun(plan, undefined, undefined, { initial: saved });
    advance(250);
    expect(heading()).toBe("Burpee");
    expect(timer()).toBe("0:50");
  });

  it("labels the logged load in kg and shows a % load in kg from the 1RM", () => {
    renderRun(section("sets", { sets: "1" }, [[ex("Back Squat", "", { cells: [{ d: "5", l: "70%" }] })]]), undefined, undefined, {
      oneRepMaxKg: () => 150,
    });
    key("Enter");
    expect(screen.getByText("70%")).toBeInTheDocument();
    expect(screen.getByText("≈ 105 kg of your 1RM")).toBeInTheDocument();
    expect(screen.getByLabelText("Load used (kg)")).toHaveAttribute("placeholder", "105");
  });
});
