"use client";

import { cloneElement, isValidElement, useState, type ReactNode } from "react";
import Link from "next/link";

import { HelpIcon, InfoModal } from "@/components/InfoModal";
import { LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { MilestoneBadges } from "@/components/member-app/progress/MilestoneBadges";
import { useLanding } from "@/components/member-app/progress/use-landing";
import type { LevelSummary, NextMilestone } from "@/api/landing";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";

/**
 * Πρόοδος's gym slots (ADR-137): rest-day banner, badges, then the scores:
 * Επίπεδο · Δύναμη · Επόμενο ορόσημο (ADR-285, they replaced «Κίνητρο»,
 * which repeated Συνέπεια) · Επιμονή · Training volume. Their windows are
 * their own (8 weeks, 7 training days), so the page's range does not narrow
 * them. The streak is in Συνέπεια (ADR-194), and a score with nothing to
 * show (no comparable lift, every badge earned, no workouts) is no card at
 * all (ANR 2026-10-24).
 */
export function ProgressOverview() {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const landing = useLanding();
  const [explain, setExplain] = useState<ScoreKind | null>(null);

  if (landing.noGym) return null;
  if (landing.isPending) return <LoadingLine />;
  if (landing.isError || !landing.data?.gamification) {
    return <QueryProblem error={landing.error} onRetry={() => void landing.refetch()} />;
  }

  const { gamification } = landing.data;
  const stats = gamification.stats;
  const perseverance = stats ? Math.round(stats.perseverance_score ?? NaN) : NaN;
  const help = (kind: ScoreKind, tooltip: string) => <HelpIcon tooltip={tooltip} onClick={() => setExplain(kind)} />;

  const cards: ReactNode[] = [];
  const level = gamification.level;
  if (level && stats && stats.total_workouts > 0) {
    cards.push(
      <ScoreCard
        key="level"
        label={i18n("scoreLevel")}
        help={help("level", i18n("scoreLevelTooltip"))}
        value={String(level.level)}
        color="var(--text)"
        meter={{ value: level.xp - level.level_start_xp, max: level.next_level_xp - level.level_start_xp, tone: "spark" }}
        caption={i18n("scoreLevelCaption", { xp: level.xp, next: level.next_level_xp, level: level.level + 1 })}
      />,
    );
  }
  const strength = gamification.strength;
  if (strength) {
    const percent = new Intl.NumberFormat(locale, { maximumFractionDigits: 1, signDisplay: "exceptZero" });
    const kg = new Intl.NumberFormat(locale, {
      style: "unit",
      unit: "kilogram",
      maximumFractionDigits: 1,
      signDisplay: "exceptZero",
    });
    cards.push(
      <ScoreCard
        key="strength"
        label={i18n("scoreStrength")}
        help={help("strength", i18n("scoreStrengthTooltip"))}
        value={`${percent.format(strength.percent)}%`}
        color="var(--success)"
        caption={i18n("scoreStrengthCaption", { weeks: Math.round(strength.window_days / 7) })}
      >
        <ul className="mt-3 flex flex-col gap-1 text-sm" aria-label={i18n("scoreStrengthLifts")}>
          {strength.lifts.map((lift) => (
            <li key={lift.name} className="flex justify-between gap-3 tabular-nums">
              <span className="min-w-0 truncate" style={{ color: "var(--muted)" }}>{lift.name}</span>
              <span className="font-semibold" style={{ color: "var(--success)" }}>{kg.format(lift.gain_kg)}</span>
            </li>
          ))}
        </ul>
      </ScoreCard>,
    );
  }
  const milestone = gamification.next_milestone;
  if (milestone) {
    cards.push(
      <ScoreCard
        key="milestone"
        label={i18n("scoreNextMilestone")}
        help={help("milestone", i18n("scoreNextMilestoneTooltip"))}
        value={String(milestone.remaining)}
        color="var(--primary)"
        meter={{ value: milestone.current, max: milestone.target, tone: "primary" }}
        caption={i18n(MILESTONE_CAPTION[milestone.kind], { remaining: milestone.remaining, target: milestone.target })}
      />,
    );
  }
  if (stats && !Number.isNaN(perseverance)) {
    cards.push(
      <ScoreCard
        key="perseverance"
        label={i18n("perseverance3b53f48")}
        help={help("perseverance", i18n("howCloselyYouFollowedPrescribedExercises760e833"))}
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
        caption={`${stats.total_prs > 0 ? `${i18n("prCount", { count: stats.total_prs })} · ` : ""}${i18n("bestStreakDays", { count: stats.longest_streak })}`}
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
      {cards.length > 0 ? (
        <section className="grid gap-4 sm:grid-cols-2">
          {/* An odd last card takes the whole row, so no card sits beside a gap. */}
          {cards.map((card, index) =>
            isValidElement<ScoreCardProps>(card) && cards.length % 2 === 1 && index === cards.length - 1
              ? cloneElement(card, { wide: true })
              : card,
          )}
        </section>
      ) : null}

      {explain ? (
        <ScoreExplainer kind={explain} level={level ?? null} onClose={() => setExplain(null)} />
      ) : null}
    </div>
  );
}

type ScoreKind = "level" | "strength" | "milestone" | "perseverance";

const MILESTONE_CAPTION = {
  workouts: "scoreNextMilestoneWorkouts",
  prs: "scoreNextMilestonePrs",
  streak: "scoreNextMilestoneStreak",
} as const satisfies Record<NextMilestone["kind"], string>;

/**
 * Each score explains itself (ANR 2026-10-30), in step with the API's
 * `Domain.Level`, `Domain.StrengthTrend`, `AchievementRules.next_milestone`
 * and `PerseveranceCalculator` (ADR-285). The XP per fact comes from the API,
 * so the explainer never drifts from what is counted.
 */
function ScoreExplainer({
  kind,
  level,
  onClose,
}: {
  kind: ScoreKind;
  level: LevelSummary | null;
  onClose: () => void;
}) {
  const i18n = useUiTranslations();
  const points = level?.points;
  const copy = {
    level: {
      title: i18n("scoreLevel"),
      what: points
        ? i18n("scoreLevelHelpWhat", {
            workouts: points.workouts,
            prs: points.prs,
            weeks: points.weeks_on_goal,
            challenges: points.challenges,
          })
        : "",
      how: i18n("scoreLevelHelpHow"),
      why: i18n("scoreLevelHelpWhy"),
    },
    strength: {
      title: i18n("scoreStrength"),
      what: i18n("scoreStrengthHelpWhat"),
      how: i18n("scoreStrengthHelpHow"),
      why: i18n("scoreStrengthHelpWhy"),
    },
    milestone: {
      title: i18n("scoreNextMilestone"),
      what: i18n("scoreNextMilestoneHelpWhat"),
      how: i18n("scoreNextMilestoneHelpHow"),
      why: i18n("scoreNextMilestoneHelpWhy"),
    },
    perseverance: {
      title: i18n("perseverance3b53f48"),
      what: i18n("perseveranceHelpWhat"),
      how: i18n("perseveranceHelpHow"),
      why: i18n("perseveranceHelpWhy"),
    },
  }[kind];

  return (
    <InfoModal title={copy.title} onClose={onClose}>
      {copy.what ? (
        <p>
          <strong style={{ color: "var(--text)" }}>{i18n("whatItMeasuresbbab752")}</strong> {copy.what}
        </p>
      ) : null}
      <p>
        <strong style={{ color: "var(--text)" }}>{i18n("howToImprove1fadc66")}</strong> {copy.how}
      </p>
      <p>
        <strong style={{ color: "var(--text)" }}>{i18n("whyItMatterscdfa2a6")}</strong> {copy.why}
      </p>
    </InfoModal>
  );
}

type ScoreCardProps = {
  label: string;
  help?: ReactNode;
  value: string;
  color: string;
  caption: string;
  meter?: { value: number; max: number; tone: "spark" | "primary" };
  wide?: boolean;
  children?: ReactNode;
};

function ScoreCard({ label, help, value, color, caption, meter, wide, children }: ScoreCardProps) {
  const share = meter && meter.max > 0 ? Math.min(100, Math.max(0, (meter.value / meter.max) * 100)) : null;
  return (
    <article
      className={`rounded-[1.9rem] p-5 ${wide ? "sm:col-span-2" : ""}`}
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div className="flex items-center gap-2">
        <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{label}</p>
        {help}
      </div>
      <p className="mt-3 text-3xl font-semibold tracking-tight tabular-nums" style={{ color }}>
        {value}
      </p>
      {share !== null ? (
        <div
          role="progressbar"
          aria-label={label}
          aria-valuemin={0}
          aria-valuemax={meter!.max}
          aria-valuenow={meter!.value}
          className="mt-3 h-2 overflow-hidden rounded-full"
          style={{ background: "var(--panel-muted)" }}
        >
          <div
            className="h-full rounded-full"
            style={{ width: `${share}%`, background: meter!.tone === "spark" ? "var(--spark)" : "var(--primary)" }}
          />
        </div>
      ) : null}
      <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>{caption}</p>
      {children}
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
