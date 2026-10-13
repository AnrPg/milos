import { describe, expect, it } from "vitest";

import {
  grantableAllowances,
  packageSubscriptionLabel,
  prSectionContentCount,
  visibleAdminProfileSections,
} from "@/components/admin/users/admin-user-profile";

describe("prSectionContentCount", () => {
  it("keeps the PR panel for staff who are not coaches so it can explain why it is empty", () => {
    expect(prSectionContentCount(undefined)).toBe(0);
    expect(prSectionContentCount({ visibility: "coach_role_required", prs: [] })).toBe(1);
    expect(prSectionContentCount({ visibility: "coach", prs: [] })).toBe(0);
    expect(prSectionContentCount({ visibility: "coach", prs: [{}, {}] })).toBe(2);
  });
});

describe("visibleAdminProfileSections", () => {
  it("keeps operational sections but removes empty person-history sections", () => {
    expect(
      visibleAdminProfileSections(
        [
          "overview",
          "finance",
          "training_history",
          "prs",
          "scores",
          "health_incidents",
          "coaching_context",
          "class_participation",
          "messages",
          "admin_actions",
        ],
        {
          training_history: 0,
          prs: 1,
          scores: 0,
          health_incidents: 0,
          coaching_context: 0,
          class_participation: 0,
          messages: 0,
        },
      ),
    ).toEqual(["overview", "finance", "prs", "admin_actions"]);
  });

  it("uses a human package label and leaves a missing label empty", () => {
    expect(packageSubscriptionLabel({ package_name: "Unlimited" })).toBe("Unlimited");
    expect(packageSubscriptionLabel({ package_code_snapshot: "LEGACY" })).toBe("LEGACY");
    expect(packageSubscriptionLabel({ package_code_snapshot: "live_coaching" })).toBe(
      "Live Coaching",
    );
    expect(packageSubscriptionLabel({})).toBe("");
  });
});

describe("grantableAllowances", () => {
  it("offers class visits first, then per-class-type limits and the plan's perks", () => {
    expect(
      grantableAllowances({
        open_gym_visits: {},
        "class_visits:b": {},
        coaching_touchpoints: {},
        guest_passes: {},
        class_visits: {},
        "class_visits:a": {},
        event_visits: {},
      }),
    ).toEqual(["class_visits", "class_visits:a", "class_visits:b", "event_visits", "guest_passes", "open_gym_visits"]);
  });

  it("offers perks alone when the plan has no class visits", () => {
    expect(grantableAllowances({ open_gym_visits: {} })).toEqual(["open_gym_visits"]);
  });

  it("falls back to class visits for an empty plan", () => {
    expect(grantableAllowances({})).toEqual(["class_visits"]);
    expect(grantableAllowances(null)).toEqual(["class_visits"]);
  });
});
