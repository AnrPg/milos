import { describe, expect, it } from "vitest";

import {
  MEMBER_PROGRAMMING_MODES,
  canProgramMorePeople,
  modeRequiresBookedClass,
  modeRequiresProgrammingEntitlement,
  programmingBlocker,
  programmingSources,
  programmingSuccessKey,
  sourceOpensEditor,
  sourceUsesClassWorkout,
} from "@/lib/member-programming";

describe("member programming rules (ADR-125)", () => {
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

  it("chooses role- and mode-aware success copy", () => {
    expect(programmingSuccessKey("athlete", "class_workout")).toBe("featurePersonalWodAssigned");
    expect(programmingSuccessKey("member", "class_variant")).toBe("memberProgrammingVariantCreated");
    expect(programmingSuccessKey("member", "personal")).toBe("memberProgrammingPersonalAssigned");
    expect(programmingSuccessKey("member", "class_workout")).toBe("featureClassWodAttached");
  });
});

describe("programming dialog steps", () => {
  const ready = {
    needsClass: true,
    hasBookedClasses: true,
    slotId: "slot-1",
    source: "library" as const,
    workoutId: "w-1",
    classHasWorkout: true,
  };

  it("offers class-based sources only for a member's own class version, adapting first", () => {
    expect(programmingSources("member", "class_variant")).toEqual(["adapt_class", "class_as_is", "library", "new"]);
    expect(programmingSources("member", "personal")).toEqual(["library", "new"]);
    expect(programmingSources("member", "class_workout")).toEqual(["library", "new"]);
    expect(programmingSources("athlete", "class_variant")).toEqual(["library", "new"]);
  });

  it("opens the editor only for sources that make a new workout", () => {
    expect(sourceOpensEditor("adapt_class")).toBe(true);
    expect(sourceOpensEditor("new")).toBe(true);
    expect(sourceOpensEditor("class_as_is")).toBe(false);
    expect(sourceOpensEditor("library")).toBe(false);
    expect(sourceUsesClassWorkout("class_as_is")).toBe(true);
    expect(sourceUsesClassWorkout("new")).toBe(false);
  });

  it("adds more people except when the whole class already gets the change", () => {
    expect(canProgramMorePeople("member", "class_workout")).toBe(false);
    expect(canProgramMorePeople("member", "class_variant")).toBe(true);
    expect(canProgramMorePeople("athlete", "class_workout")).toBe(true);
  });

  it("names the first missing step, in the order the dialog asks for them", () => {
    expect(programmingBlocker(ready)).toBeNull();
    expect(programmingBlocker({ ...ready, hasBookedClasses: false, slotId: "" })).toBe("programmingDialogNoClass");
    expect(programmingBlocker({ ...ready, slotId: "", workoutId: "" })).toBe("programmingMissingClass");
    expect(programmingBlocker({ ...ready, source: "adapt_class", classHasWorkout: false })).toBe("memberProgrammingClassHasNoWorkout");
    expect(programmingBlocker({ ...ready, workoutId: "" })).toBe("programmingMissingWod");
    expect(programmingBlocker({ ...ready, needsClass: false, hasBookedClasses: false, slotId: "", source: "new" })).toBeNull();
  });
});
