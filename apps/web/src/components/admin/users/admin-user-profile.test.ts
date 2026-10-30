import { describe, expect, it } from "vitest";

import {
  dossierMode,
  filterDossierMembers,
  grantableAllowances,
  membershipDateCards,
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

describe("dossierMode", () => {
  const base = { profileLoading: false, profileLoaded: false, actorCoaches: true, prsLoading: false, prs: undefined };
  const member = { id: "m1", nickname: "ana" };

  it("renders the full dossier whenever the profile loads", () => {
    expect(dossierMode({ ...base, profileLoading: true })).toBe("loading");
    expect(dossierMode({ ...base, profileLoaded: true })).toBe("full");
  });

  it("falls back to the PR dossier for a coach outside their client scope", () => {
    expect(dossierMode({ ...base, prsLoading: true })).toBe("loading");
    expect(dossierMode({ ...base, prs: { visibility: "coach", member } })).toBe("prs_only");
  });

  it("does not fall back for non-coaches or people who are not active in the gym", () => {
    expect(dossierMode({ ...base, actorCoaches: false, prs: { visibility: "coach", member } })).toBe("unavailable");
    expect(dossierMode({ ...base, prs: { visibility: "coach", member: null } })).toBe("unavailable");
    expect(dossierMode({ ...base, prs: { visibility: "coach_role_required", member } })).toBe("unavailable");
  });
});

describe("filterDossierMembers", () => {
  const members = [{ nickname: "Ana" }, { nickname: "bruno" }, { nickname: "Anastasia" }];

  it("matches nicknames case-insensitively and caps the list", () => {
    expect(filterDossierMembers(members, " an ")).toEqual([{ nickname: "Ana" }, { nickname: "Anastasia" }]);
    expect(filterDossierMembers(members, "", 2)).toEqual([{ nickname: "Ana" }, { nickname: "bruno" }]);
    expect(filterDossierMembers(members, "zz")).toEqual([]);
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

describe("membershipDateCards", () => {
  it("puts the start before the end, with or without a current subscription", () => {
    expect(membershipDateCards(true)).toEqual(["starts_on", "subscription_end"]);
    expect(membershipDateCards(false)).toEqual(["starts_on", "expires_on"]);
  });
});
