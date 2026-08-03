import { describe, expect, it } from "vitest";

import {
  packageSubscriptionLabel,
  visibleAdminProfileSections,
} from "@/components/admin/users/admin-user-profile";

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
