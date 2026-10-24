"use client";

import { useQuery } from "@tanstack/react-query";
import React, { useMemo, useState } from "react";

import { fetchAdminAnalyticsSummary } from "@/api/analytics";
import { HelpTooltip } from "@/components/HelpTooltip";
import { SemanticLabel } from "@/components/semantic-label";
import { useSession } from "@/components/session-provider";
import { formatClock } from "@/components/workouts/execution/TimerDisplay";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { getFormatLabels, type SectionFormat } from "@/types/workout";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/** Shape of the `execution` block of the admin analytics summary. */
export type ExecutionKpiReport = {
  started: number;
  completed: number;
  completion_rate: number | null;
  score_capture_rate: number | null;
  skip_rate_on_countdowns: number | null;
  skips: number;
  pauses_per_execution: number | null;
  average_paused_ms: number | null;
  median_time_to_first_start_ms: number | null;
  median_completed_duration_ms: number | null;
  clock_adjustment_rate: number | null;
  finish_wizard_drop_off_rate: number | null;
  abandon_points: { format: string; section_name: string | null; segment_index: number; count: number }[];
  abandon_by_format: { format: string; count: number; share: number | null }[];
  by_format: { key: string; started: number; completed: number; completion_rate: number | null }[];
  by_source: { key: string; started: number; completed: number; completion_rate: number | null }[];
  structured: { started: number; completed: number };
  free_text: { started: number; completed: number; completion_rate: number | null; median_abandon_elapsed_ms: number | null };
  daily: { date: string; started: number; completed: number }[];
};

const PERIODS = [7, 30, 90] as const;

/** An ISO date ("2026-10-12") as midnight UTC. */
function utcDay(isoDate: string) {
  const [year, month, day] = isoDate.split("-").map(Number);
  return new Date(Date.UTC(year!, (month ?? 1) - 1, day ?? 1));
}
const COMPLETED_COLOR = "var(--primary)";
const OPEN_COLOR = "color-mix(in srgb, var(--muted) 45%, var(--panel))";

export function readExecutionKpis(payload: unknown): ExecutionKpiReport | null {
  const execution = payload && typeof payload === "object" ? (payload as Record<string, unknown>).execution : null;
  if (!execution || typeof execution !== "object") return null;
  const report = execution as Partial<ExecutionKpiReport>;
  return {
    started: report.started ?? 0,
    completed: report.completed ?? 0,
    completion_rate: report.completion_rate ?? null,
    score_capture_rate: report.score_capture_rate ?? null,
    skip_rate_on_countdowns: report.skip_rate_on_countdowns ?? null,
    skips: report.skips ?? 0,
    pauses_per_execution: report.pauses_per_execution ?? null,
    average_paused_ms: report.average_paused_ms ?? null,
    median_time_to_first_start_ms: report.median_time_to_first_start_ms ?? null,
    median_completed_duration_ms: report.median_completed_duration_ms ?? null,
    clock_adjustment_rate: report.clock_adjustment_rate ?? null,
    finish_wizard_drop_off_rate: report.finish_wizard_drop_off_rate ?? null,
    abandon_points: report.abandon_points ?? [],
    abandon_by_format: report.abandon_by_format ?? [],
    by_format: report.by_format ?? [],
    by_source: report.by_source ?? [],
    structured: report.structured ?? { started: 0, completed: 0 },
    free_text: report.free_text ?? { started: 0, completed: 0, completion_rate: null, median_abandon_elapsed_ms: null },
    daily: report.daily ?? [],
  };
}

/** Workout execution health (audit §1.3): where athletes finish, skip, pause and stop. */
export function ExecutionKpiDashboard() {
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const { tokens } = useSession();
  const [days, setDays] = useState<(typeof PERIODS)[number]>(30);
  const query = useQuery({
    queryKey: ["admin", "analytics", "summary", days],
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchAdminAnalyticsSummary(tokens!.access_token, days),
  });
  const report = readExecutionKpis(query.data);
  const formatLabels = useMemo(() => getFormatLabels(i18n), [i18n]);

  const percent = (value: number | null) =>
    value === null ? "—" : new Intl.NumberFormat(uiLocale, { style: "percent", maximumFractionDigits: 0 }).format(value);
  const decimal = (value: number | null) =>
    value === null ? "—" : new Intl.NumberFormat(uiLocale, { maximumFractionDigits: 1 }).format(value);
  const duration = (ms: number | null) => (ms === null ? "—" : formatClock(Math.round(ms / 1000)));
  const formatName = (format: string) =>
    format === "free_text"
      ? i18n("authoringModeFreeText")
      : format === "unknown"
        ? i18n("kpiUnknownFormat")
        : formatLabels[format as SectionFormat] ?? format;

  return (
    <section
      aria-labelledby="execution-kpis-title"
      className="rounded-[1.6rem] border border-[color:var(--border)] bg-[var(--panel)] p-6"
    >
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <p className="text-xs font-bold uppercase tracking-[0.2em] text-[var(--primary)]">{i18n("kpiEyebrow")}</p>
          <h2 id="execution-kpis-title" className="mt-2 text-xl font-black">{i18n("kpiTitle")}</h2>
          <p className="mt-1 max-w-2xl text-sm text-[var(--muted)]">{i18n("kpiDescription")}</p>
        </div>
        <div role="group" aria-label={i18n("kpiPeriodLabel")} className="flex gap-1 rounded-full bg-[var(--panel-muted)] p-1">
          {PERIODS.map((period) => (
            <button
              key={period}
              type="button"
              aria-pressed={days === period}
              onClick={() => setDays(period)}
              className="min-h-9 rounded-full px-3 text-sm font-semibold"
              style={
                days === period
                  ? { background: "var(--primary)", color: "var(--primary-contrast)" }
                  : { color: "var(--text-soft)" }
              }
            >
              {i18n("kpiLastDays", { days: period })}
            </button>
          ))}
        </div>
      </div>

      {query.error instanceof Error ? (
        <ErrorNotice className="mt-4">{localizeError(query.error, i18n)}</ErrorNotice>
      ) : null}

      {!report ? (
        <p className="mt-6 text-sm text-[var(--muted)]">{query.isLoading ? i18n("kpiLoading") : i18n("noCapturedFactsInThisReportingWindowdc344c7")}</p>
      ) : (
        <>
          <div className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <StatTile
              label={i18n("kpiCompletionRate")}
              value={percent(report.completion_rate)}
              detail={i18n("kpiCompletedOfStarted", { completed: report.completed, started: report.started })}
              help={i18n("kpiCompletionRateHelp")}
            />
            <StatTile label={i18n("kpiScoreCapture")} value={percent(report.score_capture_rate)} help={i18n("kpiScoreCaptureHelp")} />
            <StatTile
              label={i18n("kpiSkipRate")}
              value={percent(report.skip_rate_on_countdowns)}
              detail={i18n("kpiSkipsTotal", { count: report.skips })}
              help={i18n("kpiSkipRateHelp")}
            />
            <StatTile
              label={i18n("kpiTimeToStart")}
              value={duration(report.median_time_to_first_start_ms)}
              help={i18n("kpiTimeToStartHelp")}
            />
            <StatTile
              label={i18n("kpiPauses")}
              value={decimal(report.pauses_per_execution)}
              detail={i18n("kpiAveragePaused", { time: duration(report.average_paused_ms) })}
              help={i18n("kpiPausesHelp")}
            />
            <StatTile
              label={i18n("kpiReviewDropOff")}
              value={percent(report.finish_wizard_drop_off_rate)}
              help={i18n("kpiReviewDropOffHelp")}
            />
            <StatTile
              label={i18n("kpiMedianDuration")}
              value={duration(report.median_completed_duration_ms)}
              help={i18n("kpiMedianDurationHelp")}
            />
            <StatTile
              label={i18n("kpiClockAdjusted")}
              value={percent(report.clock_adjustment_rate)}
              help={i18n("kpiClockAdjustedHelp")}
            />
          </div>

          <DailyTrend daily={report.daily} />

          <div className="mt-6 grid gap-4 lg:grid-cols-2">
            <Panel title={i18n("kpiAbandonByFormat")} help={i18n("kpiAbandonByFormatHelp")}>
              {report.abandon_by_format.length === 0 ? (
                <Empty />
              ) : (
                <ul className="space-y-3">
                  {report.abandon_by_format.map((row) => (
                    <li key={row.format}>
                      <div className="flex justify-between gap-3 text-sm">
                        <span className="text-[var(--text-soft)]">{formatName(row.format)}</span>
                        <span className="font-bold tabular-nums">
                          {row.count} · {percent(row.share)}
                        </span>
                      </div>
                      <Meter value={row.share ?? 0} color={COMPLETED_COLOR} label={formatName(row.format)} />
                    </li>
                  ))}
                </ul>
              )}
            </Panel>

            <Panel title={i18n("kpiAbandonPoints")} help={i18n("kpiAbandonPointsHelp")}>
              {report.abandon_points.length === 0 ? (
                <Empty />
              ) : (
                <table className="w-full text-start text-sm">
                  <thead>
                    <tr className="text-xs text-[var(--muted)]">
                      <th className="pb-2 text-start font-semibold">{i18n("kpiColumnWhere")}</th>
                      <th className="pb-2 text-end font-semibold">{i18n("kpiColumnPart")}</th>
                      <th className="pb-2 text-end font-semibold">{i18n("kpiColumnCount")}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {report.abandon_points.map((row, index) => (
                      <tr key={index} className="border-t border-[color:var(--border)]">
                        <td className="py-2">
                          <span className="font-semibold">{row.section_name || formatName(row.format)}</span>
                          {row.section_name ? <span className="text-[var(--muted)]"> · {formatName(row.format)}</span> : null}
                        </td>
                        <td className="py-2 text-end tabular-nums text-[var(--muted)]">{row.segment_index + 1}</td>
                        <td className="py-2 text-end font-bold tabular-nums">{row.count}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </Panel>

            <RatesTable
              title={i18n("kpiCompletionByFormat")}
              rows={report.by_format.map((row) => ({ ...row, label: formatName(row.key) }))}
              percent={percent}
            />
            <RatesTable
              title={i18n("kpiCompletionBySource")}
              rows={report.by_source.map((row) => ({ ...row, label: <SemanticLabel value={row.key} /> }))}
              percent={percent}
            />
          </div>

          <div className="mt-4 grid gap-3 sm:grid-cols-2">
            <StatTile
              label={i18n("kpiStructuredWorkouts")}
              value={i18n("kpiCompletedOfStarted", { completed: report.structured.completed, started: report.structured.started })}
            />
            <StatTile
              label={i18n("authoringModeFreeText")}
              value={i18n("kpiCompletedOfStarted", { completed: report.free_text.completed, started: report.free_text.started })}
              detail={i18n("kpiFreeTextAbandonedAt", { time: duration(report.free_text.median_abandon_elapsed_ms) })}
              help={i18n("kpiFreeTextHelp")}
            />
          </div>
        </>
      )}
    </section>
  );
}

function StatTile({ label, value, detail, help }: { label: string; value: string; detail?: string; help?: string }) {
  return (
    <div className="rounded-2xl border border-[color:var(--border)] bg-[var(--bg)] p-4">
      <div className="flex items-center gap-2">
        <p className="text-xs font-bold uppercase tracking-[0.14em] text-[var(--muted)]">{label}</p>
        {help ? <HelpTooltip label={label}>{help}</HelpTooltip> : null}
      </div>
      <p className="mt-2 text-2xl font-black tabular-nums">{value}</p>
      {detail ? <p className="mt-1 text-xs text-[var(--muted)]">{detail}</p> : null}
    </div>
  );
}

function Panel({ title, help, children }: { title: string; help?: string; children: React.ReactNode }) {
  return (
    <article className="rounded-2xl border border-[color:var(--border)] bg-[var(--bg)] p-5">
      <div className="mb-4 flex items-center gap-2">
        <h3 className="text-base font-black">{title}</h3>
        {help ? <HelpTooltip label={title}>{help}</HelpTooltip> : null}
      </div>
      {children}
    </article>
  );
}

function Empty() {
  const i18n = useUiTranslations();
  return <p className="text-sm text-[var(--muted)]">{i18n("noCapturedFactsInThisReportingWindowdc344c7")}</p>;
}

function Meter({ value, color, label }: { value: number; color: string; label: string }) {
  const width = Math.max(0, Math.min(1, value)) * 100;
  return (
    <div
      role="meter"
      aria-label={label}
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={Math.round(width)}
      className="mt-1.5 h-2 rounded-full bg-[var(--panel-muted)]"
    >
      <div className="h-2 rounded-full" style={{ width: `${width > 0 ? Math.max(width, 3) : 0}%`, background: color }} />
    </div>
  );
}

function RatesTable({
  title,
  rows,
  percent,
}: {
  title: string;
  rows: { key: string; label: React.ReactNode; started: number; completed: number; completion_rate: number | null }[];
  percent: (value: number | null) => string;
}) {
  const i18n = useUiTranslations();
  return (
    <Panel title={title}>
      {rows.length === 0 ? (
        <Empty />
      ) : (
        <table className="w-full text-sm">
          <thead>
            <tr className="text-xs text-[var(--muted)]">
              <th className="pb-2 text-start font-semibold">{i18n("kpiColumnWhat")}</th>
              <th className="pb-2 text-end font-semibold">{i18n("kpiColumnStarted")}</th>
              <th className="w-1/3 pb-2 text-end font-semibold">{i18n("kpiCompletionRate")}</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.key} className="border-t border-[color:var(--border)]">
                <td className="py-2">{row.label}</td>
                <td className="py-2 text-end tabular-nums text-[var(--muted)]">{row.started}</td>
                <td className="py-2 text-end">
                  <span className="font-bold tabular-nums">{percent(row.completion_rate)}</span>
                  <Meter value={row.completion_rate ?? 0} color={COMPLETED_COLOR} label={String(row.key)} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </Panel>
  );
}

/** Started executions per day, split into completed and not completed. */
function DailyTrend({ daily }: { daily: ExecutionKpiReport["daily"] }) {
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const [hovered, setHovered] = useState<number | null>(null);
  const [showTable, setShowTable] = useState(false);
  const max = Math.max(1, ...daily.map((day) => day.started));
  const dayLabel = (date: string) =>
    new Intl.DateTimeFormat(uiLocale, { day: "numeric", month: "short", timeZone: "UTC" }).format(utcDay(date));

  return (
    <Panel title={i18n("kpiDailyTrend")}>
      <div className="mb-3 flex flex-wrap items-center justify-between gap-3 text-xs text-[var(--text-soft)]">
        <div className="flex gap-4" aria-hidden="true">
          <span className="flex items-center gap-1.5">
            <span className="h-2.5 w-2.5 rounded-sm" style={{ background: COMPLETED_COLOR }} />
            {i18n("kpiLegendCompleted")}
          </span>
          <span className="flex items-center gap-1.5">
            <span className="h-2.5 w-2.5 rounded-sm" style={{ background: OPEN_COLOR }} />
            {i18n("kpiLegendNotCompleted")}
          </span>
        </div>
        <button
          type="button"
          onClick={() => setShowTable((value) => !value)}
          aria-expanded={showTable}
          className="font-semibold text-[var(--primary)]"
        >
          {showTable ? i18n("kpiShowChart") : i18n("kpiShowTable")}
        </button>
      </div>

      {daily.length === 0 ? (
        <Empty />
      ) : showTable ? (
        <table className="w-full text-sm">
          <thead>
            <tr className="text-xs text-[var(--muted)]">
              <th className="pb-2 text-start font-semibold">{i18n("kpiColumnDate")}</th>
              <th className="pb-2 text-end font-semibold">{i18n("kpiColumnStarted")}</th>
              <th className="pb-2 text-end font-semibold">{i18n("kpiLegendCompleted")}</th>
            </tr>
          </thead>
          <tbody>
            {daily.map((day) => (
              <tr key={day.date} className="border-t border-[color:var(--border)]">
                <td className="py-1.5">{dayLabel(day.date)}</td>
                <td className="py-1.5 text-end tabular-nums">{day.started}</td>
                <td className="py-1.5 text-end tabular-nums">{day.completed}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : (
        <div className="relative">
          <div
            role="img"
            aria-label={i18n("kpiDailyTrendSummary", {
              days: daily.length,
              started: daily.reduce((sum, day) => sum + day.started, 0),
              completed: daily.reduce((sum, day) => sum + day.completed, 0),
            })}
            className="flex h-40 items-end gap-[2px] border-b border-[color:var(--border)]"
            onMouseLeave={() => setHovered(null)}
          >
            {daily.map((day, index) => {
              const open = day.started - day.completed;
              return (
                <div
                  key={day.date}
                  className="flex h-full min-w-0 flex-1 cursor-default flex-col justify-end"
                  onMouseEnter={() => setHovered(index)}
                  onFocus={() => setHovered(index)}
                  onBlur={() => setHovered(null)}
                  tabIndex={0}
                  aria-label={i18n("kpiDayTooltip", { date: dayLabel(day.date), started: day.started, completed: day.completed })}
                >
                  <div className="flex flex-col gap-[2px]" style={{ opacity: hovered === null || hovered === index ? 1 : 0.55 }}>
                    {open > 0 ? (
                      <div className="rounded-t-[4px]" style={{ height: `${(open / max) * 152}px`, background: OPEN_COLOR }} />
                    ) : null}
                    {day.completed > 0 ? (
                      <div
                        className={open > 0 ? "" : "rounded-t-[4px]"}
                        style={{ height: `${(day.completed / max) * 152}px`, background: COMPLETED_COLOR }}
                      />
                    ) : null}
                  </div>
                </div>
              );
            })}
          </div>
          <div className="mt-1 flex justify-between text-[11px] text-[var(--muted)]">
            <span>{dayLabel(daily[0]!.date)}</span>
            <span>{dayLabel(daily.at(-1)!.date)}</span>
          </div>
          {hovered !== null && daily[hovered] ? (
            <div
              role="tooltip"
              className="pointer-events-none absolute top-0 z-10 rounded-lg border border-[color:var(--border)] bg-[var(--panel)] px-3 py-2 text-xs shadow-lg"
              style={{
                insetInlineStart: `min(calc(${((hovered + 0.5) / daily.length) * 100}% + 8px), calc(100% - 10rem))`,
              }}
            >
              <div className="font-semibold">{dayLabel(daily[hovered].date)}</div>
              <div className="text-[var(--text-soft)]">
                {i18n("kpiColumnStarted")}: <span className="font-bold tabular-nums">{daily[hovered].started}</span>
              </div>
              <div className="text-[var(--text-soft)]">
                {i18n("kpiLegendCompleted")}: <span className="font-bold tabular-nums">{daily[hovered].completed}</span>
              </div>
            </div>
          ) : null}
        </div>
      )}
    </Panel>
  );
}
