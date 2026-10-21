"use client";

import { useId, useMemo, useState } from "react";
import Link from "next/link";
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
import { ClientCard, ClientPage, EmptyLine, LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { FilterChipRow, type FilterChip } from "@/components/filters/FilterChipRow";
import { ChoiceChips, FilterPage, FilterSection } from "@/components/filters/FilterPage";
import { useRememberedFilter } from "@/components/filters/use-remembered-filter";
import { HistoryExportCard } from "@/components/member-app/progress/HistoryExportCard";
import { ProgressOverview } from "@/components/member-app/progress/ProgressOverview";
import { RestingHeartRateCard } from "@/components/devices/RestingHeartRateCard";
import { PantheonSection } from "@/components/pantheon/PantheonSection";
import { formatDay } from "@/components/client/format";
import { scaleWeekly, sparklinePoints, type WeeklyMetric } from "@/components/client/progress";
import { SourceLabel } from "@/components/providers/SourceLabel";
import { useSourceDirectory } from "@/components/providers/use-providers";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";
import { DEFAULT_PROGRESS_FILTER, parseProgressFilter } from "@/lib/account-filters";
import { sourceColor, sourceOptions, sourceToken } from "@/lib/provider-sources";
import { useTranslations } from "next-intl";

/**
 * Ημερολόγιο › Πρόοδος (ADR-137): streak, badges and scores for everyone,
 * resting heart rate from a connected device (ADR-161, only with data),
 * then personal records, the history export and the statistics across every
 * provider (ADR-162, board 17 Q4): «Όλοι» by default, a provider chip next to
 * the time range narrows it.
 */
export function ProgressConsole() {
  const i18n = useUiTranslations();
  return (
    <ClientPage title={i18n("clProgressTitle")} intro={i18n("clProgressIntro")}>
      <ProgressOverview />
      <RestingHeartRateCard />
      <PantheonSection />
      <HistoryExportCard />
      <ProgressContent />
    </ClientPage>
  );
}

function ProgressContent() {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const { filter, setFilter } = useRememberedFilter("progress", parseProgressFilter, DEFAULT_PROGRESS_FILTER);
  const query = useQuery({
    queryKey: [...ACCOUNT_PROGRESS_KEY, token, filter],
    enabled: Boolean(token) && filter !== null,
    queryFn: () => fetchAccountProgress(token!, filter!),
    placeholderData: (previous) => previous,
  });

  return (
    <div className="flex flex-col gap-4">
      {filter ? <ProgressFilters filter={filter} onChange={setFilter} /> : null}
      {filter === null || query.isPending ? (
        <LoadingLine />
      ) : query.isError ? (
        <QueryProblem error={query.error} onRetry={() => void query.refetch()} />
      ) : !query.data?.totals ? null : (
        <>
          <Totals progress={query.data} />
          <WeeklyChart progress={query.data} />
          <div className="grid gap-4 md:grid-cols-2">
            <Consistency progress={query.data} />
            <BySource progress={query.data} />
          </div>
          <PRTimeline entries={query.data.pr_timeline ?? []} />
          <ScoreHistory series={query.data.score_history ?? []} />
        </>
      )}
    </div>
  );
}

/** Time range, then «Όλοι ▾» (every provider) to narrow by source. */
function ProgressFilters({ filter, onChange }: { filter: ProgressQuery; onChange: (filter: ProgressQuery) => void }) {
  const t = useTranslations("Providers");
  const directory = useSourceDirectory();
  const [pageOpen, setPageOpen] = useState(false);
  const sources = sourceOptions(directory, {
    freeform: t("source.freeform"),
    device: t("source.device"),
    former: (name) => t("source.former", { name }),
  });
  const chips: FilterChip[] = [
    {
      key: "range",
      kind: "menu",
      label: t(`range.${filter.range}`),
      options: PROGRESS_RANGES.map((range) => ({ value: range, label: t(`range.${range}`) })),
      selected: [filter.range],
      multiple: false,
      onChange: (values) => onChange({ ...filter, range: (values[0] as ProgressQuery["range"]) ?? DEFAULT_PROGRESS_FILTER.range }),
    },
    {
      key: "sources",
      kind: "menu",
      label: t("filter.allSources"),
      options: sources,
      selected: filter.sources,
      multiple: true,
      onChange: (values) => onChange({ ...filter, sources: values }),
    },
  ];
  const count = (filter.sources.length > 0 ? 1 : 0) + (filter.exercise ? 1 : 0);
  const clear = () => onChange({ ...DEFAULT_PROGRESS_FILTER, range: filter.range });
  return (
    <>
      <FilterChipRow
        ariaLabel={t("filter.title")}
        activeCount={count}
        onOpenFilters={() => setPageOpen(true)}
        onClear={clear}
        chips={chips}
      />
      {pageOpen ? (
        <FilterPage title={t("filter.title")} onClose={() => setPageOpen(false)} onClear={clear}>
          <FilterSection label={t("filter.exercise")}>
            <input
              type="search"
              aria-label={t("filter.exercise")}
              placeholder={t("filter.exercisePlaceholder")}
              defaultValue={filter.exercise ?? ""}
              maxLength={100}
              onBlur={(event) => onChange({ ...filter, exercise: event.target.value.trim() || null })}
              onKeyDown={(event) => {
                if (event.key === "Enter") onChange({ ...filter, exercise: event.currentTarget.value.trim() || null });
              }}
              className="min-h-11 w-full rounded-2xl px-4 text-sm outline-none"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
            />
          </FilterSection>
          <FilterSection label={t("filter.source")}>
            <ChoiceChips
              ariaLabel={t("filter.source")}
              options={sources}
              selected={filter.sources}
              multiple
              onChange={(values) => onChange({ ...filter, sources: values })}
            />
          </FilterSection>
        </FilterPage>
      ) : null}
    </>
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
  const bars = useMemo(() => scaleWeekly(progress.weekly, metric), [progress.weekly, metric]);
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
              className="rounded-full px-3 py-1 text-xs font-semibold"
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
      <ol className="flex h-40 items-end gap-1 sm:gap-2" aria-label={`${i18n("clProgressWeekly")} · ${metricLabel}`}>
        {bars.map((bar) => (
          <li
            key={bar.week_start}
            className="flex h-full min-w-0 flex-1 flex-col items-center justify-end gap-1"
            aria-label={i18n("clProgressWeekOf", { date: shortDate(bar.week_start), value: bar.value })}
          >
            <span aria-hidden="true" className="text-[10px] tabular-nums" style={{ color: "var(--dim)" }}>
              {bar.value > 0 ? bar.value : ""}
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

function Consistency({ progress }: { progress: ProgressStats }) {
  const i18n = useUiTranslations();
  const { consistency } = progress;
  const percent = Math.min(100, Math.max(0, consistency.percent));
  return (
    <ClientCard title={i18n("clProgressConsistency")}>
      <p className="text-3xl font-semibold tabular-nums" style={{ color: "var(--text)" }}>
        {i18n("clPercentValue", { value: percent })}
      </p>
      <div
        role="progressbar"
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={percent}
        aria-label={i18n("clProgressConsistency")}
        className="mt-2 h-2 w-full overflow-hidden rounded-full"
        style={{ background: "var(--border)" }}
      >
        <div className="h-full rounded-full" style={{ width: `${percent}%`, background: "var(--success)" }} />
      </div>
      <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>
        {i18n("clProgressActiveWeeks", { active: consistency.active_weeks, weeks: consistency.weeks })}
      </p>
      <p className="mt-3 text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        {i18n("clProgressStreak")}
      </p>
      <p className="mt-1 text-lg font-semibold" style={{ color: "var(--text)" }}>
        {i18n("clProgressStreakWeeks", { count: consistency.current_streak_weeks })}
      </p>
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
  return (
    <ClientCard title={t("progress.bySource")}>
      {bySource.length === 0 || total === 0 ? (
        <EmptyLine>{i18n("clProgressSourcesEmpty")}</EmptyLine>
      ) : (
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
      )}
    </ClientCard>
  );
}

function ScoreHistory({ series }: { series: AccountScoreSeries[] }) {
  const i18n = useUiTranslations();
  return (
    <ClientCard title={i18n("clProgressScores")}>
      <p className="mb-3 text-sm" style={{ color: "var(--muted)" }}>{i18n("clProgressScoresIntro")}</p>
      {series.length === 0 ? (
        <EmptyLine>{i18n("clProgressScoresEmpty")}</EmptyLine>
      ) : (
        <ul className="flex flex-col gap-3">
          {series.map((item) => (
            <ScoreSeries key={`${item.workout_id}:${item.section_id ?? ""}`} series={item} />
          ))}
        </ul>
      )}
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
        className="mt-2 text-xs font-semibold"
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
  // Same cache as the Pantheon's full PR list; the modal needs the PR record.
  const prs = useQuery({
    queryKey: ["prs", "export-all"],
    enabled: Boolean(tokens?.access_token) && entries.length > 0,
    queryFn: () => listPRs(tokens!.access_token),
  });
  const prById = useMemo(() => new Map((prs.data ?? []).map((pr) => [pr.id, pr])), [prs.data]);

  return (
    <ClientCard title={i18n("clPrTimelineTitle")}>
      {months.length === 0 ? (
        <div className="flex flex-col items-start gap-3">
          <EmptyLine>{i18n("clPrTimelineEmpty")}</EmptyLine>
          <Link
            href="/journal/pantheon"
            className="rounded-full px-4 py-2 text-sm font-semibold"
            style={{ background: "var(--border)", color: "var(--text)" }}
          >
            {i18n("clPrOpenPantheon")}
          </Link>
        </div>
      ) : (
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
      )}
      {openPr ? <PRHistoryModal pr={openPr} onClose={() => setOpenPr(null)} /> : null}
    </ClientCard>
  );
}
