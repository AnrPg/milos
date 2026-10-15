import { useState } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import {
  createTrainingLogEntry,
  fetchTrainingLogSources,
  listTrainingLogEntries,
  voidTrainingLogEntry,
  type TrainingLogEntry,
} from "@/api/training-log";
import {
  TrainingLogDialog,
  TrainingLogEntryCard,
  type TrainingLogDialogState,
} from "@/components/training-log/TrainingLog";

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "token" } }),
}));

vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string, params?: Record<string, unknown>) =>
    params ? `${key}:${JSON.stringify(params)}` : key,
}));

vi.mock("@/i18n/use-ui-locale", () => ({ useUiLocale: () => "en" }));

vi.mock("@/i18n/presentation", () => ({
  localizeError: (error: Error) => error.message,
}));

vi.mock("@/api/training-log", () => ({
  listTrainingLogEntries: vi.fn(),
  fetchTrainingLogSources: vi.fn(),
  createTrainingLogEntry: vi.fn(),
  updateTrainingLogEntry: vi.fn(),
  voidTrainingLogEntry: vi.fn(),
}));

const loggedEntry = {
  id: "entry-1",
  source_type: "class",
  title: "Morning CrossFit",
  performed_at_utc: "2026-10-11T07:00:00Z",
  performed_at_tz: "UTC",
  duration_seconds: 3600,
  perceived_effort: 8,
  notes: null,
  status: "logged",
  lock_version: 1,
  section_scores: [],
  exercise_modifications: [],
  performed_exercises: [],
} as unknown as TrainingLogEntry;

// The flow pages own the dialog state; this harness wires a card to the
// dialog the same way Ημερολόγιο › Ροή and Νέα καταχώρηση do.
function Harness({ initial }: { initial: TrainingLogDialogState }) {
  const [state, setState] = useState<TrainingLogDialogState>(initial);
  return (
    <>
      <ul>
        <TrainingLogEntryCard
          entry={loggedEntry}
          locale="en"
          onEdit={() => setState({ mode: "edit", entry: loggedEntry })}
          onVoid={() => setState({ mode: "void", entry: loggedEntry })}
        />
      </ul>
      <button type="button" onClick={() => setState({ mode: "pick" })}>trainingLogLogWorkout</button>
      {state.mode !== "closed" ? (
        <TrainingLogDialog state={state} token="token" onNavigate={setState} onClose={() => setState({ mode: "closed" })} />
      ) : null}
    </>
  );
}

function renderSection(initial: TrainingLogDialogState = { mode: "closed" }) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <Harness initial={initial} />
    </QueryClientProvider>,
  );
}

describe("training log card and dialog", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(listTrainingLogEntries).mockResolvedValue([loggedEntry]);
    vi.mocked(fetchTrainingLogSources).mockResolvedValue({
      classes: [],
      assignments: [],
      library_workouts: [],
    });
  });

  it("lists logged entries with duration and effort", async () => {
    renderSection();

    expect(await screen.findByText("Morning CrossFit")).toBeInTheDocument();
    expect(screen.getByText(/trainingLogDurationMinutes:\{"minutes":60\}/)).toBeInTheDocument();
    expect(screen.getByText(/trainingLogEffortValue:\{"effort":8\}/)).toBeInTheDocument();
  });

  it("logs a freeform workout through the source picker", async () => {
    vi.mocked(createTrainingLogEntry).mockResolvedValue({ ...loggedEntry, id: "entry-2" });
    renderSection();

    fireEvent.click(await screen.findByText("trainingLogLogWorkout"));
    expect(await screen.findByText("trainingLogNoClasses")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("tab", { name: "trainingLogSourceFreeform" }));
    fireEvent.click(screen.getByText("trainingLogStartFreeform"));

    fireEvent.click(screen.getByText("trainingLogSave"));
    expect(await screen.findByText("trainingLogErrorTitleRequired")).toBeInTheDocument();
    expect(createTrainingLogEntry).not.toHaveBeenCalled();

    fireEvent.change(screen.getByLabelText("trainingLogFormTitle"), { target: { value: "Park run" } });
    fireEvent.change(screen.getByLabelText("trainingLogFormDuration"), { target: { value: "30" } });
    fireEvent.click(screen.getByText("trainingLogSave"));

    await waitFor(() => expect(createTrainingLogEntry).toHaveBeenCalledTimes(1));
    const [, payload] = vi.mocked(createTrainingLogEntry).mock.calls[0];
    expect(payload).toMatchObject({
      source_type: "freeform",
      source_reference_id: null,
      title: "Park run",
      duration_seconds: 1800,
    });
    expect(payload.idempotency_key).toMatch(/^log-/);
  });

  it("voids an entry with an optional reason", async () => {
    vi.mocked(voidTrainingLogEntry).mockResolvedValue({ ...loggedEntry, status: "voided" });
    renderSection();

    fireEvent.click(await screen.findByText("trainingLogVoid"));
    fireEvent.change(screen.getByLabelText("trainingLogVoidReason"), { target: { value: "Duplicate" } });
    fireEvent.click(screen.getByText("trainingLogVoidAction"));

    await waitFor(() =>
      expect(voidTrainingLogEntry).toHaveBeenCalledWith("token", "entry-1", {
        reason: "Duplicate",
        expected_version: 1,
      }),
    );
  });
});
