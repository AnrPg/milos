import { describe, expect, it } from "vitest";

import { badgeTier } from "@/components/member-app/progress/badges";

describe("badgeTier", () => {
  it.each([
    ["workouts_1", "bronze"],
    ["workouts_10", "silver"],
    ["workouts_50", "gold"],
    ["workouts_200", "platinum"],
    ["prs_5", "silver"],
    ["prs_25", "gold"],
    ["prs_50", "platinum"],
    ["streak_30", "silver"],
    ["streak_90", "gold"],
    ["amrap_mastery", "master"],
    ["something_else", "bronze"],
  ])("%s is %s", (key, tier) => {
    expect(badgeTier(key)).toBe(tier);
  });
});
