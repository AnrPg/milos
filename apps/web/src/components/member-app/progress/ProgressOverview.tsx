"use client";

import { useState } from "react";
import Link from "next/link";

import { HelpIcon, InfoModal } from "@/components/InfoModal";
import { LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { StreakBadges } from "@/components/member-app/progress/StreakBadges";
import { useLanding } from "@/components/member-app/progress/use-landing";
import { useUiTranslations } from "@/i18n/ui";

/**
 * Πρόοδος's first slots (ADR-137): rest-day banner, streak and badges, then
 * Motivation · Perseverance · Training volume. These were the member landing's
 * hero and stats strip before the four-tab app.
 */
export function ProgressOverview() {
  const i18n = useUiTranslations();
  const landing = useLanding();
  const [activeInfoModal, setActiveInfoModal] = useState<"streak" | "volume" | null>(null);

  if (landing.isPending) return <LoadingLine />;
  if (landing.isError || !landing.data?.gamification) {
    return <QueryProblem error={landing.error} onRetry={() => void landing.refetch()} />;
  }

  const { gamification } = landing.data;
  const stats = gamification.stats;
  const weeklyWorkoutTarget = gamification.settings.weekly_workout_target;

  return (
    <div className="flex flex-col gap-4">
      <OffDaysBanner
        offDays={gamification.preferences?.off_days ?? []}
        preferencesSet={gamification.preferences !== null && gamification.preferences !== undefined}
      />
      <StreakBadges
        streak={stats?.current_streak ?? 0}
        advancementCount={stats?.advancement_count ?? 0}
        badges={gamification.badges}
        onExplainStreak={() => setActiveInfoModal("streak")}
      />
      {stats ? (
        <section className="grid gap-4 sm:grid-cols-3">
          <article className="rounded-[1.9rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <div className="flex items-center gap-2">
              <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{i18n("motivationd6a0619")}</p>
              <HelpIcon tooltip={i18n("workoutFrequencyVsWeeklyTargetLast10Weeks28c26ce")} onClick={() => setActiveInfoModal("volume")} />
            </div>
            {isNaN(Math.round(stats.motivation_score ?? NaN)) ? (
              <p className="mt-3 text-base font-semibold" style={{ color: "var(--dim)" }}>
                {stats.total_workouts === 0
                  ? i18n("noWorkoutsYet85a9204")
                  : weeklyWorkoutTarget === 0
                    ? i18n("setAWeeklyTargetdd70e51")
                    : i18n("calculatingc573779")}
              </p>
            ) : (
              <p className="mt-3 text-3xl font-semibold tracking-tight" style={{ color: "var(--success)" }}>
                {Math.round(stats.motivation_score)}%
              </p>
            )}
            <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>{i18n("last10WeeksVsTarget153cf63")}</p>
          </article>

          <article className="rounded-[1.9rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <div className="flex items-center gap-2">
              <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{i18n("perseverance3b53f48")}</p>
              <HelpIcon tooltip={i18n("howCloselyYouFollowedPrescribedExercises760e833")} onClick={() => setActiveInfoModal("volume")} />
            </div>
            {isNaN(Math.round(stats.perseverance_score ?? NaN)) ? (
              <p className="mt-3 text-base font-semibold" style={{ color: "var(--dim)" }}>
                {stats.total_workouts === 0 ? i18n("noWorkoutsYet85a9204") : i18n("calculatingc573779")}
              </p>
            ) : (
              <p className="mt-3 text-3xl font-semibold tracking-tight" style={{ color: "var(--primary)" }}>
                {Math.round(stats.perseverance_score)}%
              </p>
            )}
            <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>{i18n("last7TrainingDays5c44037")}</p>
          </article>

          <article className="rounded-[1.9rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{i18n("trainingVolume11e038b")}</p>
            <p className="mt-3 text-3xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>
              {stats.total_workouts}
            </p>
            <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>
              {stats.total_prs > 0 ? `${stats.total_prs} ${i18n("prs80e1569")} ` : ""}
              {i18n("bestStreak04df811")} {stats.longest_streak} {i18n("days5548ae4")}
            </p>
          </article>
        </section>
      ) : null}

      {activeInfoModal === "streak" ? (
        <InfoModal title={i18n("currentStreak031c4ed")} onClose={() => setActiveInfoModal(null)}>
          <p>
            <strong style={{ color: "var(--text)" }}>{i18n("whatItMeasuresbbab752")}</strong> {i18n("theNumberOfConsecutiveUserRelativeTrainingWeeks23b79ed")} {i18n("workoutCount", { count: weeklyWorkoutTarget })}.
          </p>
          <p>
            <strong style={{ color: "var(--text)" }}>{i18n("howToImprove1fadc66")}</strong> {i18n("completeAtLeastfd38f65")} {i18n("workoutCount", { count: weeklyWorkoutTarget })} {i18n("eachTrainingWeekAStreakShieldCanProtecte2b0f06")}
          </p>
          <p>
            <strong style={{ color: "var(--text)" }}>{i18n("whyItMatterscdfa2a6")}</strong> {i18n("streaksBuildTheHabitOfRegularWeeklyTraining48e3b44")}
          </p>
        </InfoModal>
      ) : null}

      {activeInfoModal === "volume" ? (
        <InfoModal title={i18n("consistencyScore4c4624c")} onClose={() => setActiveInfoModal(null)}>
          <p>
            <strong style={{ color: "var(--text)" }}>{i18n("whatItMeasuresbbab752")}</strong> {i18n("thePercentageOfWeeksInTheLast12b38b745")} {i18n("workoutCount", { count: weeklyWorkoutTarget })}.
          </p>
          <p>
            <strong style={{ color: "var(--text)" }}>{i18n("howToImprove1fadc66")}</strong> {i18n("showUpConsistentlyCompleteAtLeast7695825")} {i18n("workoutCount", { count: weeklyWorkoutTarget })} {i18n("perWeekToCountThatWeekTowardYourc1cfc10")}
          </p>
          <p>
            <strong style={{ color: "var(--text)" }}>{i18n("whyItMatterscdfa2a6")}</strong> {i18n("consistencyOverTimePredictsLongTermAthleticProgress04e2415")}
          </p>
        </InfoModal>
      ) : null}
    </div>
  );
}

function OffDaysBanner({ offDays, preferencesSet }: { offDays: number[]; preferencesSet: boolean }) {
  const i18n = useUiTranslations();
  const [dismissed, setDismissed] = useState(false);
  const todayDow = new Date().getDay(); // 0=Sun..6=Sat

  if (dismissed) return null;

  if (!preferencesSet) {
    return (
      <div
        className="flex items-start justify-between gap-4 rounded-2xl px-5 py-4"
        style={{ background: "color-mix(in srgb, var(--warning) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--warning) 30%, transparent)" }}
      >
        <div>
          <p className="text-sm font-semibold" style={{ color: "var(--warning)" }}>
            {i18n("setYourRestDaysForAccurateMetrics6a7d46c")}
          </p>
          <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>
            {i18n("yourConsistencyAndPerseveranceScoresExcludeYourSchedulede6962c7")}
          </p>
          <Link
            href="/me/settings#training-schedule"
            className="mt-2 inline-block text-sm font-semibold underline-offset-2 hover:underline"
            style={{ color: "var(--warning)" }}
          >
            {i18n("setYourRestDaysInProfilefd0fbe4")}
          </Link>
        </div>
        <button
          type="button"
          onClick={() => setDismissed(true)}
          className="shrink-0 text-sm font-semibold"
          style={{ color: "var(--dim)" }}
        >
          {i18n("dismiss70afe9e")}
        </button>
      </div>
    );
  }

  if (!offDays.includes(todayDow)) return null;

  return (
    <div
      className="flex items-center justify-between gap-4 rounded-2xl px-5 py-3"
      style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 30%, transparent)" }}
    >
      <p className="text-sm font-semibold" style={{ color: "var(--primary)" }}>
        {i18n("todayIsYourScheduledRestDayRecoveryIse1d7a10")}
      </p>
      <button
        type="button"
        onClick={() => setDismissed(true)}
        className="shrink-0 text-sm font-semibold"
        style={{ color: "var(--dim)" }}
      >
        {i18n("dismiss70afe9e")}
      </button>
    </div>
  );
}

// ── Member/Athlete hero ───────────────────────────────────────────────────────
