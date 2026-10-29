import { describe, expect, it } from "vitest";

import el from "../../messages/el.json";
import { semanticLabel } from "@/i18n/presentation";
import {
  familiesOfWorkoutTypes,
  isWorkoutType,
  offeredWorkoutTypeGroups,
  WORKOUT_TYPE_FAMILIES,
  WORKOUT_TYPES,
  workoutTypeFamily,
  workoutTypesOfFamilies,
} from "./workout-types";

// ADR-275: one fixed list of workout kinds, grouped in families.
describe("workout types", () => {
  it("keeps the original six kinds valid", () => {
    for (const type of ["crossfit", "strength", "gymnastics", "aerobics", "flexibility", "recovery"]) {
      expect(isWorkoutType(type)).toBe(true);
    }
  });

  it("offers martial arts and dance kinds", () => {
    expect(workoutTypeFamily("muay_thai")).toBe("combat");
    expect(workoutTypeFamily("bjj_grappling")).toBe("combat");
    expect(workoutTypeFamily("dance")).toBe("dance");
    expect(workoutTypeFamily("pole_aerial")).toBe("dance");
    expect(workoutTypeFamily("unknown")).toBeNull();
    expect(isWorkoutType("unknown")).toBe(false);
  });

  it("lists every kind once", () => {
    expect(new Set(WORKOUT_TYPES).size).toBe(WORKOUT_TYPES.length);
  });

  it("names every kind and family in Greek", () => {
    const ui = el.Ui as Record<string, string>;
    const translate = ((key: string) => ui[key] ?? `missing:${key}`) as Parameters<typeof semanticLabel>[1];
    for (const type of WORKOUT_TYPES) {
      const label = semanticLabel(type, translate);
      expect(label, type).not.toMatch(/^missing:/);
      expect(label, type).not.toBe(type.replaceAll("_", " "));
    }
    for (const { family } of WORKOUT_TYPE_FAMILIES) {
      expect((el.WorkoutTypes.family as Record<string, string>)[family], family).toBeTruthy();
    }
  });

  it("offers the gym's kinds by family, keeping a workout's own hidden kind", () => {
    const groups = offeredWorkoutTypeGroups(["crossfit", "boxing"], "yoga");
    expect(groups).toEqual([
      { family: "functional", types: ["crossfit"] },
      { family: "mind_body", types: ["yoga"] },
      { family: "combat", types: ["boxing"] },
    ]);
    expect(offeredWorkoutTypeGroups(null).flatMap((group) => group.types)).toEqual(WORKOUT_TYPES);
  });

  it("turns a family filter into its kinds and back", () => {
    expect(workoutTypesOfFamilies(["dance"])).toEqual(["dance", "dance_fitness", "pole_aerial"]);
    expect(familiesOfWorkoutTypes(["kickboxing", "crossfit"])).toEqual(["functional", "combat"]);
  });
});
