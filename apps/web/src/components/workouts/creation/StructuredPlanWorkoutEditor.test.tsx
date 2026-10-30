import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { createRef } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../../messages/el.json";
import { backSquat, differentRounds } from "@/components/workouts/plan-view/plan-fixtures";
import { usePlanEditorStore } from "@/stores/structured-plan";

import { StructuredPlanWorkoutEditor, type PlanEditorHandle } from "./StructuredPlanWorkoutEditor";

const api = vi.hoisted(() => ({
  createDraftWorkout: vi.fn(),
  fetchAdminWorkout: vi.fn(),
  listScaleLevels: vi.fn(),
  publishWorkoutDraft: vi.fn(),
  updateDraftWorkout: vi.fn(),
  // ADR-275: the type picker reads the gym's workout kinds.
  WOD_ASSISTANT_AVAILABILITY_KEY: ["authoring-settings"],
  fetchWorkoutAuthoringSettings: vi.fn(async () => ({ wod_assistant_enabled: true, workout_types: ["strength", "crossfit"] })),
}));

vi.mock("@/api/workouts", () => api);
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));
vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));
vi.mock("@/components/wod-goals/WodGoalsEditorPanel", () => ({ WodGoalsEditorPanel: () => null }));
// The editor UI is its own module (plan-editor/); here only its store matters.
vi.mock("@/components/workouts/plan-editor", () => ({
  PlanEditor: () => {
    const sections = usePlanEditorStore((state) => state.sections);
    return (
      <div data-testid="plan-editor">
        {sections.map((section) => (
          <span key={section.id} data-testid="plan-section-card">
            {section.name}
          </span>
        ))}
      </div>
    );
  },
}));

const storedPlan = backSquat();
const workout = (more: Record<string, unknown> = {}) => ({
  id: "d1",
  title: "Δευτέρα",
  type: "strength",
  authoring_mode: "structured_plan",
  dsl_source_revision: 4,
  workout_metadata: { plan_note: "Ζέσταμα" },
  sections: [{ id: "s1", name: "Δύναμη", plan: storedPlan }],
  available_scale_levels: [],
  ...more,
});

function renderEditor(props: Partial<Parameters<typeof StructuredPlanWorkoutEditor>[0]> = {}) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const onPublished = vi.fn();
  const onDraftReady = vi.fn();
  const handleRef = createRef<PlanEditorHandle | null>() as { current: PlanEditorHandle | null };
  render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el}>
        <StructuredPlanWorkoutEditor draftId="d1" onDraftReady={onDraftReady} onPublished={onPublished} handleRef={handleRef} {...props} />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
  return { onPublished, onDraftReady, handleRef };
}

beforeEach(() => {
  vi.clearAllMocks();
  usePlanEditorStore.getState().load({});
  api.listScaleLevels.mockResolvedValue([{ slug: "rx", label: "RX", sort_order: 1, is_active: true }]);
  api.updateDraftWorkout.mockImplementation(async () => ({ id: "d1", dsl_source_revision: 5 }));
  api.publishWorkoutDraft.mockResolvedValue({ id: "d1" });
  api.createDraftWorkout.mockResolvedValue({ id: "new" });
});

describe("StructuredPlanWorkoutEditor", () => {
  it("loads a plan draft into the editor store", async () => {
    api.fetchAdminWorkout.mockResolvedValue(workout());
    renderEditor();
    expect(await screen.findByTestId("plan-section-card")).toHaveTextContent("Δύναμη");
    const doc = usePlanEditorStore.getState().serialize();
    expect(doc).toMatchObject({ title: "Δευτέρα", note: "Ζέσταμα" });
    expect(doc.sections[0]!.plan).toEqual(storedPlan);
    expect(api.updateDraftWorkout).not.toHaveBeenCalled();
  });

  it("autosaves changes as structured_plan with each section's plan and no exercises", async () => {
    api.fetchAdminWorkout.mockResolvedValue(workout());
    renderEditor();
    await screen.findByTestId("plan-section-card");
    act(() => usePlanEditorStore.getState().renameSection(usePlanEditorStore.getState().sections[0]!.id, "Δύναμη A"));
    await waitFor(() => expect(api.updateDraftWorkout).toHaveBeenCalled(), { timeout: 3000 });
    const [, id, payload] = api.updateDraftWorkout.mock.calls.at(-1)!;
    expect(id).toBe("d1");
    expect(payload).toMatchObject({
      title: "Δευτέρα",
      type: "strength",
      authoring_mode: "structured_plan",
      expected_source_revision: 4,
      workout_metadata: { plan_note: "Ζέσταμα" },
      sections: [{ name: "Δύναμη A", order: 1, plan: storedPlan }],
    });
    expect(payload.sections[0]).not.toHaveProperty("exercises");
    expect(payload.draft_data.sections[0].plan).toEqual(storedPlan);
  });

  it("turns a text draft into a plan with the text as the first note, and saves it as a plan", async () => {
    api.fetchAdminWorkout.mockResolvedValue(workout({ authoring_mode: "free_text", free_text_body: "AMRAP 12", sections: [] }));
    renderEditor();
    await screen.findByTestId("plan-section-card");
    expect(usePlanEditorStore.getState().sections[0]!.plan.note).toBe("AMRAP 12");
    await waitFor(() => expect(api.updateDraftWorkout).toHaveBeenCalled(), { timeout: 3000 });
    expect(api.updateDraftWorkout.mock.calls[0]![2]).toMatchObject({ authoring_mode: "structured_plan" });
  });

  it("publishes through the save queue and hands the workout back", async () => {
    api.fetchAdminWorkout.mockResolvedValue(workout());
    const { onPublished } = renderEditor();
    await screen.findByTestId("plan-section-card");
    fireEvent.click(screen.getByTestId("plan-publish"));
    await waitFor(() => expect(onPublished).toHaveBeenCalledWith("d1"));
    const [, id, payload] = api.publishWorkoutDraft.mock.calls[0]!;
    expect(id).toBe("d1");
    expect(payload).toMatchObject({ authoring_mode: "structured_plan", sections: [{ plan: storedPlan }] });
    expect(payload.expected_source_revision).toBeTypeOf("number");
  });

  it("does not publish an empty plan or one without a type", async () => {
    api.fetchAdminWorkout.mockResolvedValue(workout({ type: null, sections: [] }));
    renderEditor();
    await screen.findByTestId("plan-editor");
    fireEvent.click(screen.getByTestId("plan-publish"));
    expect(await screen.findByText("sectionedEditorNeedsTitleAndType")).toBeInTheDocument();
    expect(api.publishWorkoutDraft).not.toHaveBeenCalled();
  });

  it("says which values do not read when the API refuses the plan", async () => {
    const { ApiError } = await import("@/api/client");
    api.fetchAdminWorkout.mockResolvedValue(workout());
    api.publishWorkoutDraft.mockRejectedValue(new ApiError(422, "bad", { code: "invalid_plan_sections", details: { sections: [] } }));
    renderEditor();
    await screen.findByTestId("plan-section-card");
    fireEvent.click(screen.getByTestId("plan-publish"));
    expect(await screen.findByText(/Κάποιες τιμές δεν διαβάζονται/)).toBeInTheDocument();
  });

  it("writes the plan out as free text when the coach switches back", async () => {
    api.fetchAdminWorkout.mockResolvedValue(workout({ sections: [{ id: "s1", name: "Γύροι", plan: differentRounds() }] }));
    const { handleRef } = renderEditor();
    await screen.findByTestId("plan-section-card");
    expect(handleRef.current?.hasContent()).toBe(true);
    await act(() => handleRef.current!.switchToText());
    const payload = api.updateDraftWorkout.mock.calls.at(-1)![2];
    expect(payload).toMatchObject({ authoring_mode: "free_text", type: "strength" });
    expect(payload.free_text_body).toBe(
      ["Ζέσταμα", "", "Γύροι · For Time", "6 γύροι · όριο 20′", "Γύρος 1, 3, 5:", "  Row 500 m", "  Burpee 15", "Γύρος 2, 4, 6:", "  Run 400 m", "  Wall Ball 20", "Σκορ: Χρόνος"].join("\n"),
    );
    expect(payload.workout_metadata).not.toHaveProperty("plan_note");
  });
});
