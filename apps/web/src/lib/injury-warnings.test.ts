import { describe, expect, it } from "vitest";

import type { AthleteInjuryWarningEntry, InjuryWarning } from "@/api/injury-warnings";
import {
  affectedExercises,
  maxWarningLevel,
  selectionKey,
  warnedAthletes,
  warningLevelFor,
  warningLevelsByUser,
} from "@/lib/injury-warnings";

function warning(overrides: Partial<InjuryWarning> = {}): InjuryWarning {
  return {
    injury_id: "i-1",
    user_id: "u-1",
    body_area: "knee",
    regions: ["knee"],
    severity: "moderate",
    level: "avoid",
    provenance: "organization",
    training_limitations: null,
    tags: [],
    exercises: [],
    ...overrides,
  };
}

const athletes: AthleteInjuryWarningEntry[] = [
  { user_id: "u-1", level: "caution", warnings: [warning({ level: "caution" })] },
  { user_id: "u-2", level: "none", warnings: [] },
  { user_id: "u-3", level: "avoid", warnings: [warning({ user_id: "u-3" })] },
  { user_id: "u-4", level: "avoid", warnings: [warning({ user_id: "u-4" })] },
];

describe("injury warning helpers", () => {
  it("picks the most severe level", () => {
    expect(maxWarningLevel([])).toBe("none");
    expect(maxWarningLevel(["caution", "none"])).toBe("caution");
    expect(maxWarningLevel(["caution", "avoid", "none"])).toBe("avoid");
  });

  it("lists only warned athletes, most severe first then by name", () => {
    const names: Record<string, string> = { "u-1": "Ann", "u-3": "Zed", "u-4": "Bea" };
    const result = warnedAthletes(athletes, (id) => names[id] ?? id);

    expect(result.map((athlete) => athlete.name)).toEqual(["Bea", "Zed", "Ann"]);
  });

  it("maps warned users to their level for badges", () => {
    const levels = warningLevelsByUser(athletes);

    expect(levels.get("u-1")).toBe("caution");
    expect(levels.get("u-3")).toBe("avoid");
    expect(levels.has("u-2")).toBe(false);
    expect(warningLevelFor(levels, "u-3")).toBe("avoid");
    expect(warningLevelFor(levels, "u-2")).toBe("none");
  });

  it("groups affected exercises by level without duplicates", () => {
    const result = affectedExercises(
      warning({
        exercises: [
          { name: "Back Squat", exercise_ref: "back-squat", level: "avoid", patterns: ["squat"], match: "catalog" },
          { name: "Run", exercise_ref: "run", level: "caution", patterns: ["running"], match: "catalog" },
          { name: "Back Squat", exercise_ref: null, level: "caution", patterns: ["squat"], match: "name" },
        ],
      }),
    );

    expect(result).toEqual({ avoid: ["Back Squat"], caution: ["Run"] });
  });

  it("builds an order-independent selection key", () => {
    expect(selectionKey(["b", "a", "b"])).toBe(selectionKey(["a", "b"]));
  });
});
