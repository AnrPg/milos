import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";
import type { MemberWorkoutGoals, StaffWorkoutGoalsResponse } from "@/api/wod-goals";

import { FeltStep } from "./FeltStep";
import { applyPick, cycleEntry } from "./MusclePickerSheet";
import { WodGoalsEditorPanel } from "./WodGoalsEditorPanel";
import { WodGoalsStripView } from "./WodGoalsStrip";

const apiRequest = vi.fn();
vi.mock("@/api/client", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/client")>()),
  apiRequest: (...args: unknown[]) => apiRequest(...args),
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));
vi.mock("@/lib/anatomy/renderer/figure-controller", () => ({ createFigure: () => new Promise(() => undefined) }));
vi.mock("@/lib/anatomy/renderer/thumbs", () => ({ renderThumb: () => new Promise(() => undefined) }));

function wrap(ui: React.ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="en" messages={en}>
        {ui}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

const muscles = [
  { id: "quadriceps", role: "primary" as const },
  { id: "glutes", role: "secondary" as const },
];

function staffResponse(saved = false): StaffWorkoutGoalsResponse {
  return {
    goals: {
      workout_id: "w-1",
      saved,
      muscles,
      qualities: ["stamina"],
      stimulus: null,
      visible_to_members: false,
      source: "suggested",
      taxonomy_version: 1,
      updated_by_id: null,
      updated_at: null,
    },
    suggestion: { muscles, qualities: ["stamina"], matched_exercises: 3, unmatched_exercises: 1, taxonomy_version: 1 },
  };
}

beforeEach(() => apiRequest.mockReset());
afterEach(() => vi.useRealTimers());

describe("WodGoalsEditorPanel", () => {
  it("shows the suggestion, saves edits, cycles roles and resets to the suggestion", async () => {
    const puts: unknown[] = [];
    apiRequest.mockImplementation(async (path: string, options?: { method?: string; body?: unknown }) => {
      if (options?.method === "PUT") {
        puts.push(options.body);
        return { ...staffResponse(true), goals: { ...staffResponse(true).goals, ...(options.body as object) } };
      }
      return staffResponse();
    });
    wrap(<WodGoalsEditorPanel workoutId="w-1" timeDomainSeconds={420} />);

    expect(await screen.findByText("Suggested from 3 exercises · 1 exercise not matched")).toBeInTheDocument();
    expect(screen.getByText("Suggestion · not saved yet")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Reset to suggestion" })).toBeDisabled();
    expect(apiRequest).toHaveBeenCalledWith("/admin/workouts/w-1/goals", { token: "token" });

    // Tapping a chip cycles its role: primary → secondary.
    fireEvent.click(screen.getByRole("button", { name: "Quadriceps, Primary. Tap to change the role." }));
    expect(screen.getByRole("button", { name: "Quadriceps, Secondary. Tap to change the role." })).toBeInTheDocument();
    await waitFor(() => expect(puts).toHaveLength(1), { timeout: 3000 });
    expect(puts[0]).toEqual({
      muscles: [
        { id: "quadriceps", role: "secondary" },
        { id: "glutes", role: "secondary" },
      ],
      qualities: ["stamina"],
      stimulus: null,
      visible_to_members: false,
    });

    fireEvent.click(screen.getByRole("button", { name: "Reset to suggestion" }));
    expect(screen.getByRole("button", { name: "Quadriceps, Primary. Tap to change the role." })).toBeInTheDocument();

    fireEvent.click(screen.getByRole("checkbox", { name: "Show goals to members" }));
    fireEvent.click(screen.getByRole("button", { name: "7′" }));
    await waitFor(() => expect(puts).toHaveLength(2), { timeout: 3000 });
    expect(puts[1]).toMatchObject({ muscles, visible_to_members: true, stimulus: "7′" });
  });

  it("asks for a draft first", () => {
    wrap(<WodGoalsEditorPanel workoutId={null} />);
    expect(screen.getByText("Goals appear once the draft is saved.")).toBeInTheDocument();
  });
});

describe("WodGoalsStripView", () => {
  const goals: MemberWorkoutGoals = {
    workout_id: "w-1",
    muscles: [...muscles, { id: "erector-spinae", role: "stabilizer" }],
    qualities: ["stamina", "power"],
    stimulus: "fast, unbroken",
    taxonomy_version: 1,
    updated_at: "2026-10-21T10:00:00Z",
  };

  it("renders nothing without goals", () => {
    const { container } = wrap(<WodGoalsStripView goals={null} />);
    expect(container).toBeEmptyDOMElement();
  });

  it("names the primary muscles and opens the sheet with every role", () => {
    wrap(<WodGoalsStripView goals={goals} />);
    expect(screen.getByText("Goals: Quadriceps")).toBeInTheDocument();
    expect(screen.getByText("fast, unbroken")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "See the goals" }));
    const sheet = screen.getByRole("dialog", { name: "Workout goals" });
    expect(sheet).toHaveTextContent("Erector spinae");
    expect(sheet).toHaveTextContent("Stabilizing");
  });
});

describe("FeltStep", () => {
  it("saves what the member felt", async () => {
    const saved: unknown[] = [];
    apiRequest.mockImplementation(async (path: string, options?: { method?: string; body?: unknown }) => {
      if (options?.method === "PUT") {
        saved.push([path, options.body]);
        return {};
      }
      return {
        entry_kind: "execution",
        entry_id: "e-1",
        voided: false,
        goals: { workout_id: "w-1", muscles, qualities: ["stamina"], stimulus: null, taxonomy_version: 1, updated_at: "2026-10-21T10:00:00Z" },
        feedback: null,
      };
    });
    const onDone = vi.fn();
    wrap(<FeltStep entryKind="execution" entryId="e-1" layout="inline" onDone={onDone} />);

    fireEvent.click(await screen.findByRole("button", { name: "Glutes" }));
    fireEvent.click(screen.getByRole("button", { name: "Stamina" }));
    expect(screen.getByRole("button", { name: /Glutes/ })).toHaveAttribute("aria-pressed", "true");
    fireEvent.click(screen.getByRole("button", { name: "Save" }));

    await waitFor(() => expect(onDone).toHaveBeenCalledWith(true));
    expect(saved).toEqual([["/me/goal-feedback/execution/e-1", { felt_muscles: ["glutes"], felt_qualities: ["stamina"] }]]);
  });

  it("offers the body alone when the workout has no goals, and skips", async () => {
    apiRequest.mockResolvedValue({ entry_kind: "training_log", entry_id: "l-1", voided: false, goals: null, feedback: null });
    const onDone = vi.fn();
    wrap(<FeltStep entryKind="training_log" entryId="l-1" layout="inline" onDone={onDone} />);
    expect(await screen.findByText("Optional: mark on the body where you felt it.")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "+ Something else" })).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Skip" }));
    expect(onDone).toHaveBeenCalledWith(false);
  });
});

describe("picker taps", () => {
  const roles = ["primary", "secondary", "stabilizer"] as const;

  it("adds a group, refines it to a head and cycles on long press", () => {
    let entries = applyPick([], [...roles], "deltoid", "group", false);
    expect(entries).toEqual([{ id: "deltoid", role: "primary" }]);
    entries = applyPick([{ id: "deltoid", role: "secondary" }], [...roles], "deltoid-anterior", "head", false);
    expect(entries).toEqual([{ id: "deltoid-anterior", role: "secondary" }]);
    entries = applyPick(entries, [...roles], "deltoid-anterior", "head", true);
    expect(entries).toEqual([{ id: "deltoid-anterior", role: "stabilizer" }]);
    expect(applyPick(entries, [...roles], "deltoid-anterior", "head", true)).toEqual([]);
    expect(cycleEntry(["felt"], "felt")).toBeNull();
  });
});
