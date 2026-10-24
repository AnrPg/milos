"use client";

import type { LandingPayload } from "@/api/landing";
import { badgeTier, TIER_ICON } from "@/components/member-app/progress/badges";
import { semanticLabel } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

/**
 * Advancements and the newest milestone badges (Πρόοδος). The streak lives
 * once, in Συνέπεια (ADR-194); with nothing earned yet the card is hidden.
 */
export function MilestoneBadges({
  advancementCount,
  badges,
}: {
  advancementCount: number;
  badges: LandingPayload["gamification"]["badges"];
}) {
  const i18n = useUiTranslations();

  function getBadgeDescription(badgeKey: string): string {
    if (badgeKey.startsWith("workouts_")) {
      const n = badgeKey.split("_")[1];
      return i18n("completedValue0Workoutsde3ccd4", {value0: n});
    }
    if (badgeKey.startsWith("prs_")) {
      const n = badgeKey.split("_")[1];
      return i18n("loggedValue0PersonalRecords6eb75e4", {value0: n});
    }
    if (badgeKey.startsWith("streak_")) {
      const n = badgeKey.split("_")[1];
      return i18n("maintainedAValue0DayTrainingStreak0dbf33c", {value0: n});
    }
    if (badgeKey.endsWith("_mastery")) {
      const type = semanticLabel(badgeKey.replace("_mastery", ""), i18n);
      return i18n("achievedMasteryInValue01e7e1ec", {value0: type});
    }
    return i18n("trainingMilestoneAchieved56dc32b");
  }

  const tieredBadges = badges.map((b, i) => ({
    ...b,
    tier: badgeTier(b.badge_key),
    description: getBadgeDescription(b.badge_key),
    isNewest: i === 0,
  }));
  if (advancementCount <= 0 && tieredBadges.length === 0) return null;

  return (
    <section
      aria-label={i18n("clProgressBadges")}
      className="rounded-3xl p-5"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <style>{`
        @keyframes fadeInUp {
          from { opacity: 0; transform: translateY(8px); }
          to   { opacity: 1; transform: translateY(0); }
        }
      `}</style>
      <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{i18n("clProgressBadges")}</p>
      <div className="mt-3 flex flex-wrap items-center gap-3">
        {/* Advancement chip */}
        {advancementCount > 0 && (
          <div
            className="flex items-baseline gap-1.5 rounded-2xl px-4 py-2.5"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
          >
            <span className="text-3xl font-bold tabular-nums" style={{ color: "var(--success)" }}>
              {advancementCount}
            </span>
            <span className="text-sm font-semibold" style={{ color: "var(--dim)" }}>{i18n("advancements7f59df0")}</span>
          </div>
        )}

        {/* Badge milestone chips */}
        {tieredBadges.slice(0, 6).map((badge, idx) => (
          <div
            key={badge.id}
            title={badge.description}
            className="flex items-center gap-1.5 rounded-2xl px-3 py-2"
            style={{
              background: "var(--panel-muted)",
              border: badge.isNewest
                ? "1px solid color-mix(in srgb, var(--primary) 60%, transparent)"
                : "1px solid var(--border)",
              boxShadow: badge.isNewest
                ? "0 0 10px color-mix(in srgb, var(--primary) 25%, transparent)"
                : "none",
              animation: "fadeInUp 0.4s ease both",
              animationDelay: (idx * 80) + "ms",
              cursor: "default",
            }}
          >
            <span className="text-base leading-none">{TIER_ICON[badge.tier]}</span>
            <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
              {badge.label}
            </span>
          </div>
        ))}
      </div>
    </section>
  );
}
