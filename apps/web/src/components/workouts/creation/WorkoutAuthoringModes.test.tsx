import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import type { MutableRefObject } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../../messages/el.json";

import type { PlanEditorHandle } from "./StructuredPlanWorkoutEditor";

const api = vi.hoisted(() => ({
  fetchAdminWorkout: vi.fn(),
  fetchWorkoutAuthoringSettings: vi.fn(),
}));
const textEditor = vi.hoisted(() => ({ save: vi.fn() }));
const planEditor = vi.hoisted(() => ({ hasContent: vi.fn(), switchToText: vi.fn() }));
const router = vi.hoisted(() => ({ replace: vi.fn(), push: vi.fn() }));
const search = vi.hoisted(() => ({ params: new URLSearchParams() }));

vi.mock("@/api/workouts", () => ({
  WOD_ASSISTANT_AVAILABILITY_KEY: ["authoring-settings"],
  fetchAdminWorkout: api.fetchAdminWorkout,
  fetchWorkoutAuthoringSettings: api.fetchWorkoutAuthoringSettings,
}));
vi.mock("next/navigation", () => ({ useRouter: () => router, useSearchParams: () => search.params }));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));
vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));
vi.mock("@/lib/organization-slug", () => ({ adminHref: (href: string) => href, useOrganizationSlug: () => null }));
vi.mock("./FreeTextWorkoutEditor", () => ({
  FreeTextWorkoutEditor: ({ saveHandleRef }: { saveHandleRef?: MutableRefObject<(() => Promise<void>) | null> }) => {
    if (saveHandleRef) saveHandleRef.current = textEditor.save;
    return <div data-testid="free-text-editor" />;
  },
}));
vi.mock("./SectionedWorkoutEditor", () => ({
  SectionedWorkoutEditor: ({ saveHandleRef }: { saveHandleRef?: MutableRefObject<(() => Promise<void>) | null> }) => {
    if (saveHandleRef) saveHandleRef.current = textEditor.save;
    return <div data-testid="sectioned-editor" />;
  },
}));
vi.mock("./StructuredPlanWorkoutEditor", () => ({
  StructuredPlanWorkoutEditor: ({ handleRef }: { handleRef?: MutableRefObject<PlanEditorHandle | null> }) => {
    if (handleRef) handleRef.current = planEditor;
    return <div data-testid="plan-editor-host" />;
  },
}));
vi.mock("./QuickTextWorkoutEditor", () => ({ QuickTextWorkoutEditor: () => <div data-testid="quick-text-editor" /> }));
vi.mock("./WorkoutCreationCanvas", () => ({ WorkoutCreationCanvas: () => <div data-testid="structured-canvas" /> }));

import { WorkoutAuthoringModes } from "./WorkoutAuthoringModes";

function renderModes(props: Parameters<typeof WorkoutAuthoringModes>[0] = {}) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el}>
        <WorkoutAuthoringModes {...props} />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

const draft = (mode: string, more: Record<string, unknown> = {}) => ({ id: "d1", title: "WOD", authoring_mode: mode, sections: [], ...more });

beforeEach(() => {
  vi.clearAllMocks();
  search.params = new URLSearchParams();
  api.fetchWorkoutAuthoringSettings.mockResolvedValue({ wod_assistant_enabled: true });
  textEditor.save.mockResolvedValue(undefined);
  planEditor.switchToText.mockResolvedValue(undefined);
  planEditor.hasContent.mockReturnValue(false);
});

describe("WorkoutAuthoringModes: free text or structured", () => {
  it("starts new workouts in free text, with the toggle on «Ελεύθερο κείμενο»", async () => {
    renderModes();
    expect(await screen.findByTestId("free-text-editor")).toBeInTheDocument();
    const toggle = screen.getByTestId("authoring-toggle");
    expect(toggle).toHaveAttribute("data-value", "text");
    expect(screen.getByRole("button", { name: "Ελεύθερο κείμενο" })).toHaveAttribute("aria-pressed", "true");
    // No draft yet: nothing to switch.
    expect(screen.getByRole("button", { name: "Δομημένο" })).toBeDisabled();
  });

  it("opens a structured plan draft in the plan editor", async () => {
    search.params = new URLSearchParams("draft=d1");
    api.fetchAdminWorkout.mockResolvedValue(draft("structured_plan"));
    renderModes();
    expect(await screen.findByTestId("plan-editor-host")).toBeInTheDocument();
    expect(screen.getByTestId("authoring-toggle")).toHaveAttribute("data-value", "structured");
  });

  it("keeps legacy modes in their own editors, without the toggle", async () => {
    search.params = new URLSearchParams("draft=d1");
    api.fetchAdminWorkout.mockResolvedValue(draft("quick_text"));
    renderModes();
    expect(await screen.findByTestId("quick-text-editor")).toBeInTheDocument();
    expect(screen.queryByTestId("authoring-toggle")).not.toBeInTheDocument();
  });

  it("switches an empty text draft to structured right away, after saving it", async () => {
    search.params = new URLSearchParams("draft=d1");
    api.fetchAdminWorkout.mockResolvedValue(draft("free_text", { free_text_body: "" }));
    renderModes();
    fireEvent.click(await screen.findByRole("button", { name: "Δομημένο" }));
    expect(await screen.findByTestId("plan-editor-host")).toBeInTheDocument();
    expect(textEditor.save).toHaveBeenCalledTimes(1);
    expect(screen.queryByTestId("authoring-switch-dialog")).not.toBeInTheDocument();
  });

  it("asks before switching text to structured, and keeps the text when cancelled", async () => {
    search.params = new URLSearchParams("draft=d1");
    api.fetchAdminWorkout.mockResolvedValue(draft("free_text", { free_text_body: "AMRAP 12\n10 burpees" }));
    renderModes();
    fireEvent.click(await screen.findByRole("button", { name: "Δομημένο" }));
    expect(await screen.findByText(/Το κείμενό σου μένει ως σημείωση της πρώτης ενότητας/)).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Άκυρο" }));
    expect(screen.getByTestId("free-text-editor")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Δομημένο" }));
    fireEvent.click(await screen.findByTestId("authoring-switch-confirm"));
    expect(await screen.findByTestId("plan-editor-host")).toBeInTheDocument();
  });

  it("asks before writing a plan out as text, then saves it as text and opens free text", async () => {
    search.params = new URLSearchParams("draft=d1");
    api.fetchAdminWorkout.mockResolvedValue(draft("structured_plan"));
    planEditor.hasContent.mockReturnValue(true);
    renderModes();
    fireEvent.click(await screen.findByRole("button", { name: "Ελεύθερο κείμενο" }));
    expect(await screen.findByText(/Το πρόγραμμα γίνεται κείμενο/)).toBeInTheDocument();
    expect(planEditor.switchToText).not.toHaveBeenCalled();

    fireEvent.click(screen.getByTestId("authoring-switch-confirm"));
    expect(await screen.findByTestId("free-text-editor")).toBeInTheDocument();
    expect(planEditor.switchToText).toHaveBeenCalledTimes(1);
  });

  it("switches an empty plan back to text without asking", async () => {
    search.params = new URLSearchParams("draft=d1");
    api.fetchAdminWorkout.mockResolvedValue(draft("structured_plan"));
    renderModes();
    fireEvent.click(await screen.findByRole("button", { name: "Ελεύθερο κείμενο" }));
    expect(await screen.findByTestId("free-text-editor")).toBeInTheDocument();
    expect(screen.queryByTestId("authoring-switch-dialog")).not.toBeInTheDocument();
  });

  it("stays put and says so when the text could not be saved", async () => {
    search.params = new URLSearchParams("draft=d1");
    api.fetchAdminWorkout.mockResolvedValue(draft("free_text", { free_text_body: "x" }));
    textEditor.save.mockRejectedValue(new Error("offline"));
    renderModes();
    fireEvent.click(await screen.findByRole("button", { name: "Δομημένο" }));
    expect(await screen.findByText(/δεν αποθηκεύτηκε πριν την αλλαγή/)).toBeInTheDocument();
    expect(screen.getByTestId("free-text-editor")).toBeInTheDocument();
  });

  it("works embedded (class form, member programming) with the draft in its own state", async () => {
    api.fetchAdminWorkout.mockResolvedValue(draft("sectioned_text", { sections: [{ name: "A", free_text_body: "" }] }));
    renderModes({ embedded: true, initialDraftId: "d1" });
    expect(await screen.findByTestId("sectioned-editor")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Δομημένο" }));
    // The section's title is text too: the coach confirms.
    fireEvent.click(await screen.findByTestId("authoring-switch-confirm"));
    expect(await screen.findByTestId("plan-editor-host")).toBeInTheDocument();
    await waitFor(() => expect(router.replace).not.toHaveBeenCalled());
  });
});
