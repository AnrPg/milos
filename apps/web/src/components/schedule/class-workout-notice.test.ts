import { describe, expect, it } from "vitest";

import { classWorkoutNoticeKind } from "@/components/schedule/ClassWorkoutNotice";
import { notificationTargetUrl } from "@/components/notifications/notification-links";

describe("ADR-176 classes without a WOD", () => {
  it("names the notice staff see", () => {
    expect(classWorkoutNoticeKind({ published: true, workout_status: "linked" })).toBeNull();
    expect(classWorkoutNoticeKind({ published: false, workout_status: "missing" })).toBe("draft");
    expect(classWorkoutNoticeKind({ published: true, workout_status: "missing" })).toBe("missing");
    expect(classWorkoutNoticeKind({ published: true, workout_status: "awaiting" })).toBe("awaiting");
    expect(classWorkoutNoticeKind({})).toBeNull();
  });

  it("opens the class from the missing-WOD alert", () => {
    expect(
      notificationTargetUrl({ type: "class_workout_missing", payload: { scheduled_class_id: "c-1" } }, "admin"),
    ).toContain("open_slot=c-1");
  });
});
