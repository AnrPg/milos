import { describe, expect, it } from "vitest";

import type { CoachAudience } from "@/api/journal";
import { coachCount, coachGroups, coachKey, coachNames, keysOf, refOf, sameKeys, toggleCoach, within } from "@/lib/coach-audience";

const audience: CoachAudience = {
  organization_ids: ["box", "nikos"],
  coaches: [
    { organization_id: "box", user_id: "maria" },
    { organization_id: "nikos", user_id: "nikos" },
  ],
  providers: [
    {
      organization_id: "box",
      name: "Box Kypseli",
      kind: "gym",
      included: true,
      coaches: [
        { user_id: "maria", name: "Maria", included: true },
        { user_id: "petros", name: "Petros", included: false },
      ],
    },
    { organization_id: "nikos", name: "Nikos PT", kind: "coach", included: true, coaches: [{ user_id: "nikos", name: null, included: true }] },
    { organization_id: "empty", name: "No coaches", kind: "gym", included: false, coaches: [] },
  ],
};

describe("coach audience", () => {
  it("keys round-trip and list the default", () => {
    expect(coachKey({ organization_id: "box", user_id: "maria" })).toBe("box:maria");
    expect(refOf("box:maria")).toEqual({ organization_id: "box", user_id: "maria" });
    expect(keysOf(audience.coaches)).toEqual(["box:maria", "nikos:nikos"]);
  });

  it("groups coaches by provider, leaving out the home provider and empty ones", () => {
    const groups = coachGroups(audience);
    expect(groups.map((group) => group.organizationId)).toEqual(["box", "nikos"]);
    expect(coachCount(groups)).toBe(3);
    // A coach without a name is shown by the provider's.
    expect(groups[1].coaches[0]).toEqual({ key: "nikos:nikos", name: "Nikos PT", included: true });
    expect(coachGroups(audience, "box").map((group) => group.organizationId)).toEqual(["nikos"]);
    expect(within(["box:maria", "nikos:nikos"], coachGroups(audience, "box"))).toEqual(["nikos:nikos"]);
  });

  it("toggles without emptying and compares as sets", () => {
    expect(toggleCoach(["box:maria"], "nikos:nikos")).toEqual(["box:maria", "nikos:nikos"]);
    expect(toggleCoach(["box:maria", "nikos:nikos"], "box:maria")).toEqual(["nikos:nikos"]);
    expect(toggleCoach(["box:maria"], "box:maria")).toEqual(["box:maria"]);
    expect(sameKeys(["a", "b"], ["b", "a"])).toBe(true);
    expect(sameKeys(["a"], ["a", "b"])).toBe(false);
    expect(coachNames(audience, ["box:petros", "nikos:nikos"])).toEqual(["Petros", "Nikos PT"]);
  });
});
