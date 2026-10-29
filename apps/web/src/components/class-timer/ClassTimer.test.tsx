import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { ClassTimerControl } from "./ClassTimerControl";
import { ClassTimerDisplay } from "./ClassTimerDisplay";

const send = vi.fn();
let hookValue: Record<string, unknown>;

vi.mock("@/hooks/useClassTimer", () => ({ useClassTimer: () => hookValue }));
vi.mock("@/i18n/ui", () => ({
  useUiTranslations: () => (key: string, params?: Record<string, unknown>) =>
    params ? `${key}:${JSON.stringify(params)}` : key,
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));
vi.mock("@/lib/organization-slug", () => ({
  adminHref: (href: string, slug: string | null) => (slug ? `/org/${slug}${href}` : href),
  useOrganizationSlug: () => "gym",
}));
vi.mock("@/lib/membership-role", () => ({ useSelectedMembershipRole: () => ({ membershipRole: "coach" }) }));
// «Στην οθόνη» has its own tests (ClassScreenPin.test.tsx).
vi.mock("./ClassScreenPin", () => ({ ClassScreenPin: () => null }));

const segments = [
  { segment_key: "s0", section_id: "a", section_name: "AMRAP 10", format: "amrap", kind: "countdown", phase: "work", duration_seconds: 600, round: null, total_rounds: null, label: "AMRAP 10", exercises: [{ id: "e1", name: "Burpees", prescription_value: 10 }] },
  { segment_key: "s1", section_id: "b", section_name: "Cool down", format: "rest", kind: "countdown", phase: "rest", duration_seconds: 120, round: null, total_rounds: null, label: "Rest", label_key: "rest", exercises: [] },
];

function setTimer(status: string, index = 0, startsInMs = 0) {
  hookValue = {
    payload: {
      class: { id: "slot-1", name: "Evening WOD", scheduled_at: "2026-10-12T18:00:00Z", duration_minutes: 60 },
      workout: { id: "w1", title: "Fight Gone Bad" },
      segments,
      timer: { status, current_segment_index: index, segment_started_at_utc: null, paused_elapsed_ms: 0, duration_adjustments: {}, timer_preset: null, lock_version: 3 },
      server_now: "2026-10-12T18:00:00Z",
    },
    position: {
      status,
      index,
      segment: segments[index],
      clock: { elapsedMs: 0, remainingMs: 600_000, limitMs: 600_000, isExpired: false, progress: 0, window: null },
      startsInMs,
    },
    connected: true,
    loadError: null,
    problem: null,
    sending: false,
    send,
  };
}

describe("class timer screens", () => {
  beforeEach(() => send.mockReset());

  it("starts the class from the remote with the chosen get-ready countdown", () => {
    setTimer("ready");
    render(<ClassTimerControl slotId="slot-1" />);

    fireEvent.click(screen.getByRole("button", { name: "0:05" }));
    fireEvent.click(screen.getByRole("button", { name: "start952f375" }));

    expect(send).toHaveBeenCalledWith({ command: "start", countdown_seconds: 5 });
    expect(screen.getByRole("button", { name: "nextbc98198" })).toBeDisabled();
  });

  it("pauses, skips, adjusts and jumps while running", () => {
    setTimer("running");
    render(<ClassTimerControl slotId="slot-1" />);

    fireEvent.click(screen.getByRole("button", { name: "pausecd21a1b" }));
    fireEvent.click(screen.getByRole("button", { name: "plusThirtySecondsLabel" }));
    fireEvent.click(screen.getByRole("button", { name: /2\. Cool down/ }));

    expect(send.mock.calls.map(([command]) => command)).toEqual([
      { command: "pause" },
      { command: "adjust", delta_seconds: 30 },
      { command: "jump", index: 1 },
    ]);
  });

  it("shows the clock, the exercises and what is next on the wall", () => {
    setTimer("running");
    render(<ClassTimerDisplay slotId="slot-1" />);

    expect(screen.getByRole("timer")).toHaveTextContent("10:00");
    expect(screen.getByText("Fight Gone Bad")).toBeInTheDocument();
    expect(screen.getByText(/nextUpLabel/)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "classTimerRemoteLink" })).toHaveAttribute("href", "/org/gym/class-timer/slot-1/control");
  });

  it("shows the get-ready countdown before the start", () => {
    setTimer("running", 0, 4_200);
    render(<ClassTimerDisplay slotId="slot-1" />);

    expect(screen.getByRole("timer")).toHaveTextContent("5");
    expect(screen.getByText("getReadyLabel")).toBeInTheDocument();
  });
});
