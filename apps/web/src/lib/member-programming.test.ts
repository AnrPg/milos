import { describe, expect, it } from "vitest";

import {
  MEMBER_PROGRAMMING_MODES,
  modeRequiresBookedClass,
  modeRequiresProgrammingEntitlement,
  programmingSuccessKey,
  yourVersionHref,
} from "@/lib/member-programming";

describe("member programming rules (ADR-115)", () => {
  it("offers the member's own class version first and the class-wide swap last", () => {
    expect(MEMBER_PROGRAMMING_MODES).toEqual(["class_variant", "personal", "class_workout"]);
  });

  it("requires a booked class only for class-bound modes", () => {
    expect(modeRequiresBookedClass("class_variant")).toBe(true);
    expect(modeRequiresBookedClass("class_workout")).toBe(true);
    expect(modeRequiresBookedClass("personal")).toBe(false);
  });

  it("requires the personal-programming package grant only for member assignments", () => {
    expect(modeRequiresProgrammingEntitlement("class_variant")).toBe(true);
    expect(modeRequiresProgrammingEntitlement("personal")).toBe(true);
    expect(modeRequiresProgrammingEntitlement("class_workout")).toBe(false);
  });

  it("links a class card's version to the auto-opening workout list", () => {
    expect(yourVersionHref("a-1", "2026-10-12")).toBe(
      "/my-workouts?open_assignment=a-1&date=2026-10-12",
    );
  });

  it("chooses role- and mode-aware success copy", () => {
    expect(programmingSuccessKey("athlete", "class_workout")).toBe("featurePersonalWodAssigned");
    expect(programmingSuccessKey("member", "class_variant")).toBe("memberProgrammingVariantCreated");
    expect(programmingSuccessKey("member", "personal")).toBe("memberProgrammingPersonalAssigned");
    expect(programmingSuccessKey("member", "class_workout")).toBe("featureClassWodAttached");
  });
});
