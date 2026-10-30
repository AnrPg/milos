"use client";

import { useId, useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";

import {
  ACCOUNT_PROGRESS_KEY,
  fetchAccountProgress,
  PROGRESS_RANGES,
  type AccountProgress,
  type AccountScoreSeries,
  type ProgressQuery,
} from "@/api/account-training";
import type { ProgressStats } from "@/api/content";
import { listPRs, type PRRecord } from "@/api/gamification";
import { PRHistoryModal } from "@/components/pantheon/PRHistoryModal";
import { formatPRScore, groupPRTimelineByMonth, prImprovement } from "@/components/client/pr-timeline";
import { semanticLabel } from "@/i18n/presentation";
import { useSession } from "@/components/session-provider";
import { HelpIcon, InfoModal } from "@/components/InfoModal";
import { ClientCard, LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import {
  consistencyGrid,
  heatStrips,
  localToday,
  weeksOnTarget,
  type HeatLevel,
} from "@/components/client/consistency";
import { FilterMenuChip, type FilterChip } from "@/components/filters/FilterChipRow";
import { useRememberedFilter } from "@/components/filters/use-remembered-filter";
import { InsightsCard } from "@/components/member-app/progress/InsightsCard";
import { ProgressDepthSections } from "@/components/member-app/progress/ProgressDepthSections";
import { ProgressOverview } from "@/components/member-app/progress/ProgressOverview";
import { useLanding } from "@/components/member-app/progress/use-landing";
import { weeklyTarget } from "@/components/training-goal/training-goal";
import { useTrainingGoal } from "@/components/training-goal/use-training-goal";
import { RestingHeartRateCard } from "@/components/devices/RestingHeartRateCard";
import { PersonalRecordsSection } from "@/components/pantheon/PersonalRecordsSection";
import { formatDay } from "@/components/client/format";
import { dailyStatsRange, scaleWeekly, sparklinePoints, type WeeklyMetric } from "@/components/client/progress";
import { SourceLabel } from "@/components/providers/SourceLabel";
import { useSourceDirectory } from "@/components/providers/use-providers";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";
import { DEFAULT_PROGRESS_FILTER, parseProgressFilter } from "@/lib/account-filters";
import { sourceColor, sourceOptions, sourceToken } from "@/lib/provider-sources";
import { useTranslations } from "next-intl";

/**
 * Ημερολόγιο › Πρόοδος (ADR-137, ADR-194; vision §7.7: «fixed section order
 * with a time range on top»). The range and «Όλοι ▾» source chips come first
 * and drive every card that has a period: Συνέπεια (calendar heatmap, the
 * one streak, weeks on target), Personal Records (each lift's estimated 1RM
 * and each benchmark's trend over the range), the statistics across every
 * provider (ADR-162), resting heart rate (ADR-161) and the depth slots
 * (ADR-165): Μυϊκή κάλυψη, Ποιότητες, Φορτίο, then Insights (ADR-166). The
 * gym's badges and scores sit after the PRs; their windows are their own.
 * The Journal header names the page, so there is no second title. A card
 * with nothing in it is hidden (ANR 2026-10-24); PRs are the «Personal
 * Records» section (`#prs`); the history export lives in Vault.
 */
export function ProgressConsole() {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const { filter: remembered, setFilter } = useRememberedFilter("progress", parseProgressFilter, DEFAULT_PROGRESS_FILTER);
  // ADR-285: the page no longer narrows by exercise (Personal Records searches
  // its own list), so an exercise remembered from before never hides data.
  const filter = useMemo(() => (remembered ? { ...remembered, exercise: null } : null), [remembered]);
  const query = useQuery({
    queryKey: [...ACCOUNT_PROGRESS_KEY, filter],
    enabled: Boolean(token) && filter !== null,
    queryFn: () => fetchAccountProgress(token!, filter!),
    placeholderData: (previous) => previous,
  });
  const progress = query.data?.totals ? query.data : null;

  return (
    <main className="min-h-screen px-4 py-6 md:px-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-4xl flex-col gap-4">
        {filter === null ? (
          <LoadingLine />
        ) : (
          <>
            <ProgressFilters
              filter={filter}
              availableSources={progress?.available_sources ?? filter.sources}
              onChange={setFilter}
            />
            {query.isPending ? (
              <LoadingLine />
            ) : query.isError ? (
              <QueryProblem error={query.error} onRetry={() => void query.refetch()} />
            ) : progress ? (
              <Consistency progress={progress} />
            ) : null}
            <PersonalRecordsSection filter={filter} />
            <ProgressOverview />
            {progress ? (
              <>
                <Totals progress={progress} />
                <WeeklyChart progress={progress} />
                <BySource progress={progress} />
              </>
            ) : null}
            <RestingHeartRateCard range={dailyStatsRange(filter.range)} />
            {progress ? (
              <>
                <PRTimeline entries={progress.pr_timeline ?? []} />
                <ScoreHistory series={progress.score_history ?? []} />
              </>
            ) : null}
            <ProgressDepthSections filter={filter} />
            <InsightsCard />
          </>
        )}
      </div>
    </main>
  );
}

/**
 * ADR-285 (ANR picked mockup Φ3, 2026-10-30): the period is a bar that is
 * always in view, one tap to change. «Πηγή ▾» shows only when the person
 * trained with two or more sources (their box, on their own, a device), or
 * while one is picked so it can be cleared. The exercise search lives in
 * Personal Records, the one section it narrows.
 */
function ProgressFilters({
  filter,
  availableSources,
  onChange,
}: {
  filter: ProgressQuery;
  availableSources: string[];
  onChange: (filter: ProgressQuery) => void;
}) {
  const t = useTranslations("Providers");
  const directory = useSourceDirectory();
  const offered = new Set([...availableSources, ...filter.sources]);
  const sources = sourceOptions(directory, {
    freeform: t("source.freeform"),
    device: t("source.device"),
    former: (name) => t("source.former", { name }),
  }).filter((option) => offered.has(option.value));
  const sourceChip: FilterChip = {
    key: "sources",
    kind: "menu",
    label: t("filter.source"),
    options: sources,
    selected: filter.sources,
    multiple: true,
    onChange: (values) => onChange({ ...filter, sources: values }),
  };
  return (
    <div className="flex items-center gap-2">
      <div
        role="group"
        aria-label={t("filter.period")}
        className="flex min-w-0 flex-1 gap-0.5 rounded-full p-1"
        style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
      >
        {PROGRESS_RANGES.map((range) => {
          const on = filter.range === range;
          return (
            <button
              key={range}
              type="button"
              aria-pressed={on}
              aria-label={t(`range.${range}`)}
              title={t(`range.${range}`)}
              onClick={() => onChange({ ...filter, range })}
              className="min-h-9 min-w-0 flex-1 whitespace-nowrap rounded-full px-2 text-sm font-semibold"
              style={
                on
                  ? { background: "var(--panel)", color: "var(--text)", boxShadow: "0 1px 3px color-mix(in srgb, var(--text) 18%, transparent)" }
                  : { background: "transparent", color: "var(--muted)" }
              }
            >
              {t(`rangeShort.${range}`)}
            </button>
          );
        })}
      </div>
      {sources.length > 1 || filter.sources.length > 0 ? <FilterMenuChip chip={sourceChip} /> : null}
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-2xl px-4 py-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <p className="text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{label}</p>
      <p className="mt-1 text-2xl font-semibold tabular-nums" style={{ color: "var(--text)" }}>{value}</p>
    </div>
  );
}

function Totals({ progress }: { progress: ProgressStats }) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const number = new Intl.NumberFormat(locale);
  return (
    <div className="grid grid-cols-1 gap-3 min-[420px]:grid-cols-3">
      <Stat label={i18n("clProgressSessions")} value={number.format(progress.totals.sessions)} />
      <Stat label={i18n("clProgressMinutes")} value={number.format(progress.totals.minutes)} />
      <Stat label={i18n("clProgressWorkouts")} value={number.format(progress.totals.workouts)} />
    </div>
  );
}

function WeeklyChart({ progress }: { progress: ProgressStats }) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const [metric, setMetric] = useState<WeeklyMetric>("sessions");
  const bars = useMemo(() => scaleWeekly(progress.weekly, metric, progress.weekly.length), [progress.weekly, metric]);
  const metricLabel = metric === "sessions" ? i18n("clProgressSessions") : i18n("clProgressMinutes");
  const shortDate = (day: string) => formatDay(day, locale, { weekday: undefined, year: undefined, month: "short" });

  return (
    <ClientCard
      title={i18n("clProgressWeekly")}
      aside={
        <div role="group" aria-label={i18n("clProgressMetric")} className="flex gap-1 rounded-full p-0.5" style={{ background: "var(--panel-muted)" }}>
          {(["sessions", "minutes"] as const).map((value) => (
            <button
              key={value}
              type="button"
              aria-pressed={metric === value}
              onClick={() => setMetric(value)}
              className="hit-area rounded-full px-3 py-1 text-xs font-semibold"
              style={{
                background: metric === value ? "var(--border)" : "transparent",
                color: metric === value ? "var(--text)" : "var(--dim)",
              }}
            >
              {value === "sessions" ? i18n("clProgressSessions") : i18n("clProgressMinutes")}
            </button>
          ))}
        </div>
      }
    >
      <ol
        className={`flex h-40 items-end ${bars.length > 26 ? "gap-px" : "gap-1 sm:gap-2"}`}
        aria-label={`${i18n("clProgressWeekly")} · ${metricLabel}`}
      >
        {bars.map((bar) => (
          <li
            key={bar.week_start}
            className="flex h-full min-w-0 flex-1 flex-col items-center justify-end gap-1"
            aria-label={i18n("clProgressWeekOf", { date: shortDate(bar.week_start), value: bar.value })}
          >
            <span aria-hidden="true" className="text-[10px] tabular-nums" style={{ color: "var(--dim)" }}>
              {bar.value > 0 && bars.length <= 26 ? bar.value : ""}
            </span>
            <span
              aria-hidden="true"
              className="w-full rounded-t-md"
              style={{
                height: `${Math.max(bar.percent, bar.value > 0 ? 4 : 1)}%`,
                background: bar.value > 0 ? "var(--primary)" : "var(--border)",
              }}
            />
          </li>
        ))}
      </ol>
      {bars.length > 0 ? (
        <div aria-hidden="true" className="mt-2 flex justify-between text-[10px]" style={{ color: "var(--dim)" }}>
          <span>{shortDate(bars[0].week_start)}</span>
          <span>{shortDate(bars[bars.length - 1].week_start)}</span>
        </div>
      ) : null}
    </ClientCard>
  );
}

const HEAT_BACKGROUND: Record<HeatLevel, string> = {
  0: "var(--panel-muted)",
  1: "color-mix(in srgb, var(--primary) 35%, transparent)",
  2: "color-mix(in srgb, var(--primary) 65%, transparent)",
  3: "var(--primary)",
};

/**
 * Συνέπεια (ADR-194, mockup `heatGrid`): the range as a calendar heatmap, a
 * column per week with a mark under each week that reached the target, the
 * one streak (the gym's day streak when there is a gym, else weeks in a row
 * with training) and the weekly target. Every day and week has a label.
 */
function Consistency({ progress }: { progress: AccountProgress }) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const landing = useLanding();
  const [explain, setExplain] = useState(false);
  const gamification = landing.data?.gamification;
  // ADR-229: my own weekly goal, with or without a gym.
  const goal = useTrainingGoal();
  const target = goal.data ? weeklyTarget(goal.data) : null;
  const dayStreak = gamification?.stats?.current_streak;
  const today = localToday();
  const weeks = useMemo(
    () => consistencyGrid(progress.weekly, progress.days ?? [], today, target),
    [progress.weekly, progress.days, today, target],
  );
  const onTarget = weeksOnTarget(weeks);
  const percent = weeks.length > 0 ? Math.round((onTarget * 100) / weeks.length) : 0;
  const shortDate = (day: string) => formatDay(day, locale, { weekday: undefined, year: undefined, month: "short" });
  const streak =
    typeof dayStreak === "number"
      ? i18n("clProgressStreakDays", { count: dayStreak })
      : i18n("clProgressStreakWeeks", { count: progress.consistency.current_streak_weeks });

  return (
    <ClientCard
      title={i18n("clProgressConsistency")}
      aside={
        <span className="flex flex-wrap items-center gap-2 text-xs font-semibold" style={{ color: "var(--muted)" }}>
          {/* THEME.md: the streak is Spark, a fill with dark text. */}
          <span className="rounded-full px-2.5 py-1" style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}>
            {i18n("clProgressStreak")}: {streak}
          </span>
          {target ? <span>{i18n("clProgressTarget", { count: target })}</span> : null}
          {target ? <HelpIcon tooltip={i18n("currentStreak031c4ed")} onClick={() => setExplain(true)} /> : null}
        </span>
      }
    >
      <p className="text-3xl font-semibold tabular-nums" style={{ color: "var(--text)" }}>
        {i18n("clPercentValue", { value: percent })}
      </p>
      <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>
        {target
          ? i18n("clProgressOnTargetWeeks", { onTarget, weeks: weeks.length })
          : i18n("clProgressActiveWeeks", { active: onTarget, weeks: weeks.length })}
      </p>
      <div className="mt-3 flex flex-col gap-3" role="group" aria-label={i18n("clProgressHeatmap")}>
        {heatStrips(weeks).map((strip) => (
          <div
            key={strip[0].week_start}
            className="grid w-full gap-[3px]"
            style={{ gridTemplateColumns: `repeat(${strip.length}, minmax(0, 1fr))`, maxWidth: `${strip.length * 1.5}rem` }}
          >
            {strip.map((week) => (
              <ol
                key={week.week_start}
                className="flex min-w-0 flex-col gap-[3px]"
                aria-label={i18n("clProgressHeatWeek", {
                  date: shortDate(week.week_start),
                  count: week.sessions,
                  onTarget: String(week.onTarget),
                })}
              >
                {week.days.map((day) => (
                  <li
                    key={day.date}
                    className="aspect-square w-full rounded-[3px]"
                    style={{
                      background: day.future ? "transparent" : HEAT_BACKGROUND[day.level],
                      border: day.future ? "1px dashed var(--border)" : undefined,
                      outline: day.date === today ? "2px solid var(--spark)" : undefined,
                      outlineOffset: day.date === today ? "1px" : undefined,
                    }}
                  >
                    <span className="sr-only">
                      {i18n("clProgressHeatDay", {
                        date: formatDay(day.date, locale, { year: undefined, month: "short" }),
                        count: day.sessions,
                      })}
                    </span>
                  </li>
                ))}
                <li
                  aria-hidden="true"
                  className="mt-0.5 h-1 w-full rounded-full"
                  style={{ background: week.onTarget ? "var(--success)" : "var(--border)" }}
                />
              </ol>
            ))}
          </div>
        ))}
      </div>
      {weeks.length > 0 ? (
        <div aria-hidden="true" className="mt-2 flex justify-between text-[10px]" style={{ color: "var(--dim)" }}>
          <span>{shortDate(weeks[0].week_start)}</span>
          <span>{shortDate(weeks[weeks.length - 1].week_start)}</span>
        </div>
      ) : null}
      {explain && target ? (
        <InfoModal title={i18n("currentStreak031c4ed")} onClose={() => setExplain(false)}>
          <p>
            <strong style={{ color: "var(--text)" }}>{i18n("whatItMeasuresbbab752")}</strong>{" "}
            {i18n("theNumberOfConsecutiveUserRelativeTrainingWeeks23b79ed")} {i18n("workoutCount", { count: target })}.
          </p>
          <p>
            <strong style={{ color: "var(--text)" }}>{i18n("howToImprove1fadc66")}</strong> {i18n("completeAtLeastfd38f65")}{" "}
            {i18n("workoutCount", { count: target })} {i18n("eachTrainingWeekAStreakShieldCanProtecte2b0f06")}
          </p>
          <p>
            <strong style={{ color: "var(--text)" }}>{i18n("whyItMatterscdfa2a6")}</strong>{" "}
            {i18n("streaksBuildTheHabitOfRegularWeeklyTraining48e3b44")}
          </p>
        </InfoModal>
      ) : null}
    </ClientCard>
  );
}

/** Sessions per provider (and freeform, devices), largest first. */
function BySource({ progress }: { progress: AccountProgress }) {
  const i18n = useUiTranslations();
  const t = useTranslations("Providers");
  const directory = useSourceDirectory();
  const bySource = progress.by_source ?? [];
  const total = bySource.reduce((sum, row) => sum + row.sessions, 0);
  if (bySource.length === 0 || total === 0) return null;
  return (
    <ClientCard title={t("progress.bySource")}>
      <ul className="flex flex-col gap-2">
        {bySource.map((row) => {
          const percent = Math.round((row.sessions / total) * 100);
          return (
            <li key={sourceToken(row.source)}>
              <div className="flex items-center justify-between gap-2 text-sm">
                <SourceLabel source={row.source} directory={directory} always />
                <span className="tabular-nums" style={{ color: "var(--dim)" }}>
                  {row.sessions} · {i18n("clPercentValue", { value: percent })}
                </span>
              </div>
              <div aria-hidden="true" className="mt-1 h-1.5 w-full overflow-hidden rounded-full" style={{ background: "var(--border)" }}>
                <div className="h-full rounded-full" style={{ width: `${percent}%`, background: sourceColor(row.source, directory) }} />
              </div>
            </li>
          );
        })}
      </ul>
    </ClientCard>
  );
}

function ScoreHistory({ series }: { series: AccountScoreSeries[] }) {
  const i18n = useUiTranslations();
  if (series.length === 0) return null;
  return (
    <ClientCard title={i18n("clProgressScores")}>
      <p className="mb-3 text-sm" style={{ color: "var(--muted)" }}>{i18n("clProgressScoresIntro")}</p>
      <ul className="flex flex-col gap-3">
        {series.map((item) => (
          <ScoreSeries key={`${item.workout_id}:${item.section_id ?? ""}`} series={item} />
        ))}
      </ul>
    </ClientCard>
  );
}

function ScoreSeries({ series }: { series: AccountScoreSeries }) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const listId = useId();
  const [open, setOpen] = useState(false);
  const points = sparklinePoints(series, 120, 28);
  const latest = series.points[series.points.length - 1];
  const unit = series.unit ? ` ${series.unit}` : "";

  return (
    <li className="rounded-xl p-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="min-w-0">
          <p className="break-words text-sm font-semibold" style={{ color: "var(--text)" }}>
            {series.workout_title ?? i18n("workout39463a5")}
          </p>
          {series.section_name ? (
            <p className="text-xs" style={{ color: "var(--dim)" }}>{series.section_name}</p>
          ) : null}
        </div>
        <div className="flex items-center gap-3">
          {points ? (
            <svg width="120" height="28" viewBox="-2 -2 124 32" aria-hidden="true" className="overflow-visible">
              <polyline points={points} fill="none" stroke="var(--primary)" strokeWidth="2" strokeLinejoin="round" strokeLinecap="round" />
            </svg>
          ) : null}
          {latest ? (
            <span className="text-sm font-semibold tabular-nums" style={{ color: "var(--text)" }}>
              <bdi>{`${String(latest.value)}${unit}`}</bdi>
            </span>
          ) : null}
        </div>
      </div>
      <button
        type="button"
        aria-expanded={open}
        aria-controls={listId}
        onClick={() => setOpen((value) => !value)}
        className="mt-2 min-h-11 text-xs font-semibold"
        style={{ color: "var(--primary)" }}
      >
        {open ? i18n("clHideDates") : i18n("clShowDates", { count: series.points.length })}
      </button>
      {open ? (
        <ol id={listId} className="mt-2 flex flex-col gap-1 text-xs">
          {series.points.map((point) => (
            <li key={point.execution_id} className="flex justify-between gap-2" style={{ color: "var(--text-soft)" }}>
              <time dateTime={point.completed_on}>
                {formatDay(point.completed_on, locale, { weekday: undefined, month: "short" })}
              </time>
              <span className="flex items-center gap-2">
                <SourceLabel source={point.source} />
                <bdi className="tabular-nums">{`${String(point.value)}${unit}`}</bdi>
              </span>
            </li>
          ))}
        </ol>
      ) : null}
    </li>
  );
}

function PRTimeline({ entries }: { entries: AccountProgress["pr_timeline"] }) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const [openPr, setOpenPr] = useState<PRRecord | null>(null);
  const months = useMemo(() => groupPRTimelineByMonth(entries), [entries]);
  // The full PR list; the modal needs the PR record.
  const prs = useQuery({
    queryKey: ["prs", "export-all"],
    enabled: Boolean(tokens?.access_token) && entries.length > 0,
    queryFn: () => listPRs(tokens!.access_token),
  });
  const prById = useMemo(() => new Map((prs.data ?? []).map((pr) => [pr.id, pr])), [prs.data]);

  if (months.length === 0) return null;
  return (
    <ClientCard title={i18n("clPrTimelineTitle")}>
      <ol className="flex flex-col gap-4">
        {months.map((month) => (
          <li key={month.month}>
            <h3 className="mb-2 text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
              <time dateTime={month.month}>
                {formatDay(`${month.month}-01`, locale, { weekday: undefined, day: undefined })}
              </time>
            </h3>
            <ol className="flex flex-col border-s-2 ps-4" style={{ borderColor: "var(--border)" }}>
              {month.entries.map((entry) => {
                const pr = prById.get(entry.pr_record_id) ?? null;
                const unit =
                  entry.unit === "mins_secs"
                    ? ""
                    : ` ${entry.unit === "kg" ? i18n("kilogramsUnit") : semanticLabel(entry.unit, i18n)}`;
                const improvement = prImprovement(entry);
                const improvementText =
                  improvement.kind === "first"
                    ? i18n("clPrFirstRecord")
                    : improvement.kind === "time_saved"
                      ? i18n("clPrTimeSaved", { time: improvement.text })
                      : `${improvement.text}${unit}`;
                return (
                  <li key={entry.id} className="relative py-1">
                    <span
                      aria-hidden="true"
                      className="absolute top-3 h-2.5 w-2.5 rounded-full"
                      style={{ insetInlineStart: "calc(-1rem - 6px)", background: "var(--primary)" }}
                    />
                    <button
                      type="button"
                      disabled={!pr}
                      onClick={() => pr && setOpenPr(pr)}
                      aria-label={i18n("clPrOpenHistory", { name: entry.name })}
                      className="w-full rounded-lg px-2 py-1.5 text-start text-sm transition-colors enabled:hover:bg-[color-mix(in_srgb,var(--text)_4%,transparent)]"
                    >
                      <span style={{ color: "var(--dim)" }}>
                        <time dateTime={entry.beaten_on}>
                          {formatDay(entry.beaten_on, locale, { weekday: undefined, year: undefined, month: "short" })}
                        </time>
                        {" · "}
                      </span>
                      <span className="font-semibold" style={{ color: "var(--text)" }}>
                        {entry.name}{" "}
                        <bdi className="tabular-nums">{`${formatPRScore(entry.score, entry.unit)}${unit}`}</bdi>
                      </span>{" "}
                      <span
                        className="tabular-nums"
                        style={{ color: improvement.kind === "first" ? "var(--dim)" : "var(--success)" }}
                      >
                        (<bdi>{improvementText}</bdi>)
                      </span>{" "}
                      <SourceLabel source={entry.source} />
                    </button>
                  </li>
                );
              })}
            </ol>
          </li>
        ))}
      </ol>
      {openPr ? <PRHistoryModal pr={openPr} onClose={() => setOpenPr(null)} /> : null}
    </ClientCard>
  );
}
