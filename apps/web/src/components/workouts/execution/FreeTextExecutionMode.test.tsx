import { act, fireEvent, render, screen } from "@testing-library/react";
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

vi.mock("@/api/executions", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/executions")>()),
  fetchExecution: () => new Promise(() => undefined),
}));

describe("FreeTextExecutionMode", () => {
  beforeEach(() => {
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
});
