import { describe, expect, it } from "vitest";

import { workoutCta } from "@/components/workout-cta";

const now = new Date("2026-07-17T10:00:00.000Z");

describe("workoutCta", () => {
  it("resumes an active execution before considering other triggers", () => {
    expect(
      workoutCta({
        role: "member",
        now,
        executions: [{ id: "execution-1", status: "paused" }],
        scheduleSlots: [],
        assignments: [],
      }),
    ).toEqual({ href: "/workouts/execution-1/execute", label: "resume" });
  });

  it("offers logging for an approved booked class within two hours", () => {
    expect(
      workoutCta({
        role: "member",
        now,
        executions: [],
        scheduleSlots: [
          {
            id: "slot-1",
            scheduled_at: "2026-07-17T11:30:00.000Z",
            current_user_booking: { status: "approved" },
          },
        ],
        assignments: [],
      }),
    ).toEqual({ href: "/schedule?open_slot=slot-1", label: "log" });
  });

  it("offers logging for an athlete assignment due today", () => {
    expect(
      workoutCta({
        role: "athlete",
        now,
        executions: [],
        scheduleSlots: [],
        assignments: [
          { id: "assignment-1", scheduled_for: "2026-07-17", execution_status: null },
        ],
      }),
    ).toEqual({ href: "/my-workouts", label: "log" });
  });

  it("hides the CTA without a qualifying trigger", () => {
    expect(
      workoutCta({
        role: "member",
        now,
        executions: [],
        scheduleSlots: [
          {
            id: "slot-1",
            scheduled_at: "2026-07-17T13:00:01.000Z",
            current_user_booking: { status: "approved" },
          },
        ],
        assignments: [],
      }),
    ).toBeNull();
  });
});
