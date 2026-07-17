import { describe, expect, it } from "vitest";

import { visibleAdminProfileSections } from "@/components/admin/users/admin-user-profile";

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
});
