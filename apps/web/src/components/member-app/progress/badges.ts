export type BadgeTier = "bronze" | "silver" | "gold" | "platinum" | "master";

/** Tier of a milestone badge from its key (`workouts_50`, `prs_5`, `streak_30`, `amrap_mastery`). */
export function badgeTier(badgeKey: string): BadgeTier {
  if (badgeKey.endsWith("_mastery")) return "master";
  const n = parseInt(badgeKey.split("_")[1] ?? "0", 10);
  if (badgeKey.startsWith("workouts_")) {
    if (n >= 200) return "platinum";
    if (n >= 50) return "gold";
    if (n >= 10) return "silver";
    return "bronze";
  }
  if (badgeKey.startsWith("prs_")) {
    if (n >= 50) return "platinum";
    if (n >= 25) return "gold";
    if (n >= 5) return "silver";
    return "bronze";
  }
  if (badgeKey.startsWith("streak_")) {
    if (n >= 90) return "gold";
    if (n >= 30) return "silver";
    return "bronze";
  }
  return "bronze";
}

export const TIER_ICON: Record<BadgeTier, string> = {
  bronze: "🥉",
  silver: "🥈",
  gold: "🥇",
  platinum: "💎",
  master: "⭐",
};
