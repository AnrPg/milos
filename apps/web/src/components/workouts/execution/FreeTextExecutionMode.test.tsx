import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { storeFreeTextExecutionWorkout } from "@/lib/free-text-execution";

import { FreeTextExecutionMode } from "./FreeTextExecutionMode";

vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string) => key,
}));

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), back: vi.fn() }),
  useSearchParams: () => new URLSearchParams({ workout: "workout-1", execution: "execution-1" }),
}));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ tokens: { access_token: "token" } }),
}));

const updateExecutionProgress = vi.fn();

vi.mock("@/api/executions", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/executions")>()),
  fetchExecution: () => Promise.resolve({ id: "execution-1", lock_version: 1, exercise_modifications: [] }),
  updateExecutionProgress: (...args: unknown[]) => updateExecutionProgress(...args),
}));

describe("FreeTextExecutionMode", () => {
  beforeEach(() => {
    updateExecutionProgress.mockReset();
    updateExecutionProgress.mockImplementation(() => Promise.resolve({ id: "execution-1", lock_version: 2 }));
    window.localStorage.clear();
    window.sessionStorage.clear();
    storeFreeTextExecutionWorkout(
      {
        id: "workout-1",
        title: "Fran",
        free_text_body: "21-15-9 thrusters and pull-ups",
        workout_metadata: { free_text_timer: { format: "amrap", duration_seconds: 600 } },
      },
      { id: "execution-1", source: "self_selected" },
    );
  });

  it("starts with the coach's timer and keeps running across a reload", async () => {
    const { unmount } = render(<FreeTextExecutionMode />);

    expect(screen.getByRole("button", { name: "coachTimerPresetLabel" })).toHaveAttribute("aria-pressed", "true");
    expect(screen.getByRole("timer")).toHaveTextContent("10:00");

    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "startTimerLabel" }));
    });
    expect(screen.getByRole("button", { name: "pausecd21a1b" })).toBeInTheDocument();

    unmount();
    render(<FreeTextExecutionMode />);
    expect(await screen.findByRole("button", { name: "pausecd21a1b" })).toBeInTheDocument();
  });

  it("switches to a quick preset", () => {
    render(<FreeTextExecutionMode />);
    fireEvent.click(screen.getByRole("button", { name: "timerPreset_tabata" }));
    expect(screen.getByRole("timer")).toHaveTextContent("0:20");
  });

  it("saves progress with pause and start counters while training", async () => {
    render(<FreeTextExecutionMode />);

    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "startTimerLabel" }));
    });
    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: "pausecd21a1b" }));
    });

    await waitFor(() => {
      const payload = updateExecutionProgress.mock.calls.at(-1)![2];
      expect(payload.status).toBe("paused");
      expect(payload.kpi_counters).toMatchObject({ pauses: 1 });
      expect(typeof payload.kpi_counters.first_started_at_ms).toBe("number");
    });
  });
});
