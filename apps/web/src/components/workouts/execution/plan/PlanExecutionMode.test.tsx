import { act, fireEvent, render, screen } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { PlanSection } from "@/lib/structured-plan/types";

import en from "../../../../../messages/en.json";
import { PlanExecutionMode } from "./PlanExecutionMode";
import { isPlanSection, planSections, usesPlanRunner } from "./plan-workout";

const api = vi.hoisted(() => ({
  fetchExecution: vi.fn(),
  fetchWorkout: vi.fn(),
  completeExecution: vi.fn(),
  save: vi.fn(),
  push: vi.fn(),
  wizard: vi.fn(),
  listPRs: vi.fn(),
}));

vi.mock("next/navigation", () => ({ useRouter: () => ({ push: api.push, replace: vi.fn(), back: vi.fn() }) }));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));
vi.mock("@/hooks/useScreenWakeLock", () => ({ useScreenWakeLock: () => undefined }));
vi.mock("@/hooks/useJournalCommentWriter", () => ({ useJournalCommentWriter: () => ({ save: api.save, remove: vi.fn() }) }));
vi.mock("@/api/executions", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/executions")>()),
  fetchExecution: api.fetchExecution,
  completeExecution: api.completeExecution,
}));
vi.mock("@/api/workouts", () => ({ fetchWorkout: api.fetchWorkout }));
vi.mock("@/api/gamification", () => ({ listPRs: api.listPRs }));
vi.mock("../FinishWizard", () => ({
  FinishWizard: (props: { scores: unknown[]; segments: unknown[]; onConfirm: (s: unknown[], f: unknown) => void }) => {
    api.wizard(props);
    return (
      <button type="button" onClick={() => props.onConfirm(props.scores, { changes: [], text: null })}>
        wizard
      </button>
    );
  },
}));

const plan = (flow: PlanSection["flow"], name: string, dose: string, score: string): PlanSection => ({
  v: 1,
  flow,
  params: flow === "for_time" ? { rounds: "1" } : { sets: "1" },
  blocks: [[{ id: `${name}-row`, kind: "ex", name, dose, load: "", cells: flow === "sets" ? [{ d: dose, l: "100kg" }] : [] }]],
  score,
});

describe("plan-workout", () => {
  it("knows plan workouts and reads their plan sections in order", () => {
    expect(usesPlanRunner({ authoring_mode: "structured_plan" })).toBe(true);
    expect(usesPlanRunner({ authoring_mode: "free_text" })).toBe(false);
    expect(isPlanSection({ v: 1, flow: "nope", params: {}, blocks: [] })).toBe(false);
    const sections = planSections({
      sections: [
        { id: "b", name: "B", order: 2, plan: plan("sets", "Squat", "5", "none") },
        { id: "x", name: "X", order: 0, plan: null },
        { id: "a", name: "A", order: 1, plan: plan("for_time", "Burpee", "10", "time") },
      ],
    });
    expect(sections.map((s) => s.id)).toEqual(["a", "b"]);
  });
});

describe("PlanExecutionMode", () => {
  beforeEach(() => {
    Object.values(api).forEach((fn) => fn.mockReset());
    api.fetchExecution.mockResolvedValue({ id: "exe-1", master_workout_id: "w-1", comments: [] });
    api.fetchWorkout.mockResolvedValue({
      id: "w-1",
      title: "Saturday",
      authoring_mode: "structured_plan",
      sections: [
        { id: "a", name: "A", order: 0, plan: plan("for_time", "Burpee", "10", "time") },
        { id: "b", name: "B", order: 1, plan: plan("sets", "Squat", "5", "none") },
      ],
    });
    api.completeExecution.mockResolvedValue({});
    api.listPRs.mockResolvedValue([]);
    window.localStorage.clear();
    api.save.mockImplementation(async (draft: { id: string; change: unknown }) => ({ comment: { id: draft.id, change: draft.change }, synced: true }));
  });

  it("keeps running when the PRs come back in an unexpected shape", async () => {
    api.listPRs.mockResolvedValue(undefined);
    render(
      <NextIntlClientProvider locale="en" messages={en}>
        <PlanExecutionMode executionId="exe-1" />
      </NextIntlClientProvider>,
    );
    expect(await screen.findByText("Section 1 of 2")).toBeInTheDocument();
    await act(async () => {
      await Promise.resolve();
    });
    fireEvent.click(screen.getByTestId("plan-run-next"));
    expect(screen.getByText("Section 1 of 2")).toBeInTheDocument();
  });

  it("runs every section in turn, logs changes and completes the execution with the scores", async () => {
    render(
      <NextIntlClientProvider locale="en" messages={en}>
        <PlanExecutionMode executionId="exe-1" />
      </NextIntlClientProvider>,
    );
    expect(await screen.findByText("Section 1 of 2")).toBeInTheDocument();

    fireEvent.click(screen.getByTestId("plan-run-next"));
    fireEvent.change(screen.getByLabelText("Reps done"), { target: { value: "8" } });
    await act(async () => {
      fireEvent.click(screen.getByTestId("plan-run-next"));
    });
    expect(api.save).toHaveBeenCalledWith(
      expect.objectContaining({
        entry_kind: "execution",
        entry_id: "exe-1",
        change: expect.objectContaining({
          patch_id: "plan:a:Burpee-row:0:1:0:0:reps",
          type: "reps_changed",
          actual_value: 8,
          canonical_value: 10,
          section_id: "a",
          exercise_id: "Burpee-row",
          exercise_name: "Burpee",
          set_index: 1,
        }),
      }),
    );
    fireEvent.change(screen.getByRole("textbox"), { target: { value: "2:10" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    expect(screen.getByText("Section 2 of 2")).toBeInTheDocument();
    fireEvent.click(screen.getByTestId("plan-run-next"));
    fireEvent.click(screen.getByTestId("plan-run-next"));
    fireEvent.click(screen.getByRole("button", { name: "Continue" }));

    expect(api.wizard).toHaveBeenLastCalledWith(
      expect.objectContaining({
        scores: [expect.objectContaining({ section_id: "a", value: "2:10" })],
        segments: [expect.objectContaining({ section_id: "a", score_config: expect.objectContaining({ type: "time", label: "Time" }) })],
      }),
    );
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "wizard" }));
    });
    expect(api.completeExecution).toHaveBeenCalledWith(
      "token",
      "exe-1",
      expect.objectContaining({
        section_scores: [expect.objectContaining({ section_id: "a", value: "2:10" })],
        section_elapsed_ms: expect.objectContaining({ a: expect.any(Number), b: expect.any(Number) }),
        plan_actuals: [
          expect.objectContaining({ section_id: "a", row_id: "Burpee-row", round_index: 1, prescribed_reps: 10, actual_reps: 8, logged: true }),
          expect.objectContaining({ section_id: "b", row_id: "Squat-row", prescribed_reps: 5, prescribed_load_kg: 100, actual_load_kg: 100, logged: false }),
        ],
      }),
    );
    expect(api.push).toHaveBeenCalledWith("/");
  });

  it("resumes after a reload where the athlete was, and forgets the run once completed", async () => {
    const view = () =>
      render(
        <NextIntlClientProvider locale="en" messages={en}>
          <PlanExecutionMode executionId="exe-1" />
        </NextIntlClientProvider>,
      );
    const first = view();
    expect(await screen.findByText("Section 1 of 2")).toBeInTheDocument();
    fireEvent.click(screen.getByTestId("plan-run-next"));
    fireEvent.change(screen.getByLabelText("Reps done"), { target: { value: "9" } });
    await act(async () => {
      fireEvent.click(screen.getByTestId("plan-run-next"));
    });
    fireEvent.change(screen.getByRole("textbox"), { target: { value: "1:00" } });
    fireEvent.click(screen.getByRole("button", { name: "Save" }));
    expect(screen.getByText("Section 2 of 2")).toBeInTheDocument();
    fireEvent.click(screen.getByTestId("plan-run-next"));
    expect(screen.getByRole("heading", { level: 2 })).toHaveTextContent("Squat");
    first.unmount();

    view();
    expect(await screen.findByText("Section 2 of 2")).toBeInTheDocument();
    expect(screen.getByRole("heading", { level: 2 })).toHaveTextContent("Squat");
    fireEvent.click(screen.getByTestId("plan-run-next"));
    fireEvent.click(screen.getByRole("button", { name: "Continue" }));
    expect(api.wizard).toHaveBeenLastCalledWith(expect.objectContaining({ scores: [expect.objectContaining({ section_id: "a", value: "1:00" })] }));
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "wizard" }));
    });
    expect(api.completeExecution).toHaveBeenCalledWith(
      "token",
      "exe-1",
      expect.objectContaining({ plan_actuals: expect.arrayContaining([expect.objectContaining({ section_id: "a", actual_reps: 9 })]) }),
    );
    expect(window.localStorage.getItem("palee:plan-run:exe-1")).toBeNull();
  });

  it("says when there is nothing to run", async () => {
    api.fetchWorkout.mockResolvedValue({ id: "w-1", title: "Empty", authoring_mode: "structured_plan", sections: [] });
    render(
      <NextIntlClientProvider locale="en" messages={en}>
        <PlanExecutionMode executionId="exe-1" />
      </NextIntlClientProvider>,
    );
    expect(await screen.findByText("This workout has nothing to run yet.")).toBeInTheDocument();
  });
});
