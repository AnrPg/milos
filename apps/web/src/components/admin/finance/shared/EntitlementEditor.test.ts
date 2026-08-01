import { describe, expect, it } from "vitest";

import {
  entitlementDraft,
  entitlementParams,
  sanitizeEntitlementDraft,
  type EntitlementDraft,
} from "./EntitlementEditor";

const draft: EntitlementDraft = {
  channels: ["in_person", "workout_library", "personal_programming"],
  capabilities: [
    "book_classes",
    "execute_library_workouts",
    "execute_assigned_workouts",
    "receive_coaching_touchpoints",
  ],
  classVisitLimit: "unlimited",
  classVisitPeriod: "calendar_month",
  coachingTouchpointLimit: "2",
  coachingTouchpointPeriod: "calendar_month",
};

describe("EntitlementEditor entitlement helpers", () => {
  it("removes blocked workout-library options from editable drafts", () => {
    expect(sanitizeEntitlementDraft(draft)).toMatchObject({
      channels: ["in_person", "personal_programming"],
      capabilities: ["book_classes", "execute_assigned_workouts", "receive_coaching_touchpoints"],
    });
  });

  it("does not persist blocked workout-library options in package params", () => {
    expect(entitlementParams(draft)).toMatchObject({
      channels: ["in_person", "personal_programming"],
      capabilities: ["book_classes", "execute_assigned_workouts", "receive_coaching_touchpoints"],
    });
  });

  it("strips blocked workout-library options loaded from existing package params", () => {
    expect(
      entitlementDraft({
        channels: ["workout_library", "in_person"],
        capabilities: ["execute_library_workouts", "execute_class_workouts"],
        allowances: {},
      }),
    ).toMatchObject({
      channels: ["in_person"],
      capabilities: ["execute_class_workouts"],
    });
  });
});
