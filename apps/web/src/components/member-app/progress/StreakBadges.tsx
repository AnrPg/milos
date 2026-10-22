"use client";

import type { LandingPayload } from "@/api/landing";
import { HelpIcon } from "@/components/InfoModal";
import { badgeTier, TIER_ICON } from "@/components/member-app/progress/badges";
import { useCountUp } from "@/components/member-app/progress/use-count-up";
import { semanticLabel } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

/** Streak, advancements and the newest milestone badges (Πρόοδος). */
export function StreakBadges({
  streak,
  advancementCount,
  badges,
  onExplainStreak,
}: {
  streak: number;
  advancementCount: number;
  badges: LandingPayload["gamification"]["badges"];
  onExplainStreak: () => void;
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

  const animatedStreak = useCountUp(streak);
  const tieredBadges = badges.map((b, i) => ({
    ...b,
    tier: badgeTier(b.badge_key),
    description: getBadgeDescription(b.badge_key),
    isNewest: i === 0,
  }));

  return (
    <section className="rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <style>{`
        @keyframes fadeInUp {
          from { opacity: 0; transform: translateY(8px); }
          to   { opacity: 1; transform: translateY(0); }
        }
      `}</style>
      <div className="flex items-center gap-2">
        <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{i18n("currentStreak031c4ed")}</p>
        <HelpIcon tooltip={i18n("currentStreak031c4ed")} onClick={onExplainStreak} />
      </div>
      {/* Streak + advancement + badge chips row */}
      <div className="mt-3 flex flex-wrap items-center gap-3">
        {/* Day streak chip */}
        <div
          className="flex items-baseline gap-1.5 rounded-2xl px-4 py-2.5"
          style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}
        >
          <span className="text-3xl font-bold tabular-nums">{animatedStreak}</span>
          <span className="text-sm font-semibold">{i18n("dayStreakca360c4")}</span>
        </div>

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

        {tieredBadges.length === 0 && (
          <p className="text-sm" style={{ color: "var(--dim)" }}>
            {i18n("completeYourFirstWorkoutToEarnYourFirst4d6cd86")}
          </p>
        )}
      </div>
    </section>
  );
}
