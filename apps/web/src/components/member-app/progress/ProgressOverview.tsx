"use client";

import { useState, type ReactNode } from "react";
import Link from "next/link";

import { HelpIcon, InfoModal } from "@/components/InfoModal";
import { LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { MilestoneBadges } from "@/components/member-app/progress/MilestoneBadges";
import { useLanding } from "@/components/member-app/progress/use-landing";
import { weeklyTarget } from "@/components/training-goal/training-goal";
import { useUiTranslations } from "@/i18n/ui";

const GRID_COLUMNS = ["", "", "sm:grid-cols-2", "sm:grid-cols-3"] as const;

/**
 * Πρόοδος's gym slots (ADR-137): rest-day banner, badges, then Motivation ·
 * Perseverance · Training volume. Their windows are the gym's own (10 weeks,
 * 7 training days), so the page's range does not narrow them. The streak is
 * in Συνέπεια (ADR-194), and a score still being worked out (no workouts,
 * no target, «calculating») is no card at all (ANR 2026-10-24).
 */
export function ProgressOverview() {
  const i18n = useUiTranslations();
  const landing = useLanding();
  const [explain, setExplain] = useState<ScoreKind | null>(null);

  if (landing.noGym) return null;
  if (landing.isPending) return <LoadingLine />;
  if (landing.isError || !landing.data?.gamification) {
    return <QueryProblem error={landing.error} onRetry={() => void landing.refetch()} />;
  }

  const { gamification } = landing.data;
  const stats = gamification.stats;
  // ADR-229: the person's own goal (the default until someone sets one).
  const weeklyWorkoutTarget = weeklyTarget(gamification.goal);
  const motivation = stats ? Math.round(stats.motivation_score ?? NaN) : NaN;
  const perseverance = stats ? Math.round(stats.perseverance_score ?? NaN) : NaN;

  const cards: ReactNode[] = [];
  if (stats && !Number.isNaN(motivation)) {
    cards.push(
      <ScoreCard
        key="motivation"
        label={i18n("motivationd6a0619")}
        help={<HelpIcon tooltip={i18n("workoutFrequencyVsWeeklyTargetLast10Weeks28c26ce")} onClick={() => setExplain("motivation")} />}
        value={`${motivation}%`}
        color="var(--success)"
        caption={i18n("last10WeeksVsTarget153cf63")}
      />,
    );
  }
  if (stats && !Number.isNaN(perseverance)) {
    cards.push(
      <ScoreCard
        key="perseverance"
        label={i18n("perseverance3b53f48")}
        help={<HelpIcon tooltip={i18n("howCloselyYouFollowedPrescribedExercises760e833")} onClick={() => setExplain("perseverance")} />}
        value={`${perseverance}%`}
        color="var(--primary)"
        caption={i18n("last7TrainingDays5c44037")}
      />,
    );
  }
  if (stats && stats.total_workouts > 0) {
    cards.push(
      <ScoreCard
        key="volume"
        label={i18n("trainingVolume11e038b")}
        value={String(stats.total_workouts)}
        color="var(--text)"
        caption={`${stats.total_prs > 0 ? `${stats.total_prs} ${i18n("prs80e1569")} ` : ""}${i18n("bestStreak04df811")} ${stats.longest_streak} ${i18n("days5548ae4")}`}
      />,
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <OffDaysBanner
        offDays={gamification.preferences?.off_days ?? []}
        preferencesSet={gamification.preferences !== null && gamification.preferences !== undefined}
      />
      <MilestoneBadges advancementCount={stats?.advancement_count ?? 0} badges={gamification.badges} />
      {cards.length > 0 ? <section className={`grid gap-4 ${GRID_COLUMNS[cards.length]}`}>{cards}</section> : null}

      {explain ? (
        <ScoreExplainer kind={explain} weeklyWorkoutTarget={weeklyWorkoutTarget} onClose={() => setExplain(null)} />
      ) : null}
    </div>
  );
}

type ScoreKind = "motivation" | "perseverance";

/**
 * Each score explains itself (ANR 2026-10-30): Κίνητρο is weeks on the
 * person's weekly goal over 10 weeks (`MotivationCalculator`), Επιμονή is how
 * closely the last 7 training days followed the prescription
 * (`PerseveranceCalculator`). Keep this copy in step with those modules.
 */
function ScoreExplainer({
  kind,
  weeklyWorkoutTarget,
  onClose,
}: {
  kind: ScoreKind;
  weeklyWorkoutTarget: number;
  onClose: () => void;
}) {
  const i18n = useUiTranslations();
  const workouts = i18n("workoutCount", { count: weeklyWorkoutTarget });
  const copy =
    kind === "motivation"
      ? {
          title: i18n("motivationd6a0619"),
          what: i18n("motivationHelpWhat", { workouts }),
          how: i18n("motivationHelpHow"),
          why: i18n("motivationHelpWhy"),
        }
      : {
          title: i18n("perseverance3b53f48"),
          what: i18n("perseveranceHelpWhat"),
          how: i18n("perseveranceHelpHow"),
          why: i18n("perseveranceHelpWhy"),
        };

  return (
    <InfoModal title={copy.title} onClose={onClose}>
      <p>
        <strong style={{ color: "var(--text)" }}>{i18n("whatItMeasuresbbab752")}</strong> {copy.what}
      </p>
      <p>
        <strong style={{ color: "var(--text)" }}>{i18n("howToImprove1fadc66")}</strong> {copy.how}
      </p>
      <p>
        <strong style={{ color: "var(--text)" }}>{i18n("whyItMatterscdfa2a6")}</strong> {copy.why}
      </p>
    </InfoModal>
  );
}

function ScoreCard({
  label,
  help,
  value,
  color,
  caption,
}: {
  label: string;
  help?: ReactNode;
  value: string;
  color: string;
  caption: string;
}) {
  return (
    <article className="rounded-[1.9rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <div className="flex items-center gap-2">
        <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{label}</p>
        {help}
      </div>
      <p className="mt-3 text-3xl font-semibold tracking-tight" style={{ color }}>
        {value}
      </p>
      <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>{caption}</p>
    </article>
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
            href="/me/sharing#training-schedule"
            className="mt-2 inline-block text-sm font-semibold underline-offset-2 hover:underline"
            style={{ color: "var(--warning)" }}
          >
            {i18n("setYourRestDaysInProfilefd0fbe4")}
          </Link>
        </div>
        <button
          type="button"
          onClick={() => setDismissed(true)}
          className="min-h-11 shrink-0 text-sm font-semibold"
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
        className="min-h-11 shrink-0 text-sm font-semibold"
        style={{ color: "var(--dim)" }}
      >
        {i18n("dismiss70afe9e")}
      </button>
    </div>
  );
}
