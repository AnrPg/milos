"use client";

import { useId, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useFormatter, useLocale, useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  DECISION_TEXT_MAX,
  PLATFORM_REPORTS_KEY,
  SUGGESTION_STATS_KEY,
  decidePlatformReport,
  fetchPlatformReports,
  fetchSuggestionStats,
  groupReportsByPerson,
  suggestionTotals,
  type ReportGroup,
} from "@/api/platform-partners";
import { dateAtNoon } from "@/components/partner-verify/verify-notifications";
import { VerifyError } from "@/components/partner-verify/verify-ui";
import { useSession } from "@/components/session-provider";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { BackLink } from "@/components/ui/BackLink";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { withClock } from "@/lib/clock";

const buttonClass = "min-h-10 px-4 text-sm font-semibold disabled:opacity-50";

/**
 * Platform console › Αναφορές Συναθλητών (ADR-280): open reports on people in
 * Partners, gathered per person. Suspending ends their Partners access and
 * pauses their sponsors; dismissing closes the reports. Either closes every
 * open report on that person. Below, the «Κλείστε μαζί» quality counters.
 */
export function PlatformPartnerReportsPage() {
  const t = useTranslations("PlatformPartners");
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const reports = useQuery({ queryKey: PLATFORM_REPORTS_KEY, enabled: Boolean(token), queryFn: () => fetchPlatformReports(token!) });
  const [done, setDone] = useState<string | null>(null);
  const forbidden = reports.error instanceof ApiError && reports.error.status === 403;
  const groups = groupReportsByPerson(reports.data?.reports ?? []);

  return (
    <main className="mx-auto w-full max-w-5xl px-4 py-8 sm:px-6" data-testid="platform-partner-reports">
      <header className="flex flex-col gap-1 border-b border-[var(--border)] pb-5">
        <BackLink href="/platform/organizations" className="text-sm text-[var(--text-soft)]">{t("back")}</BackLink>
        <h1 className="text-3xl font-semibold text-[var(--text)]">{t("reports.title")}</h1>
        <p className="text-sm text-[var(--text-soft)]">{t("reports.subtitle")}</p>
      </header>
      {forbidden ? <p className="mt-6 text-[var(--text-soft)]">{t("forbidden")}</p> : null}
      {reports.error && !forbidden ? <div className="mt-6"><VerifyError error={reports.error} /></div> : null}
      {done ? <p role="status" className="mt-4 text-sm font-semibold text-[var(--success)]">{done}</p> : null}
      {token && reports.data ? (
        <section className="mt-6 flex flex-col gap-3" aria-label={t("reports.title")}>
          {groups.length === 0 ? <p className="text-sm text-[var(--text-soft)]">{t("reports.empty")}</p> : null}
          {groups.map((group) => (
            <ReportGroupCard key={group.target.id} token={token} group={group} onDone={setDone} />
          ))}
        </section>
      ) : null}
      {token && !forbidden ? <SuggestionStatsCard token={token} /> : null}
    </main>
  );
}

function ReportGroupCard({ token, group, onDone }: { token: string; group: ReportGroup; onDone: (message: string) => void }) {
  const t = useTranslations("PlatformPartners");
  const format = useFormatter();
  const locale = useLocale();
  const queryClient = useQueryClient();
  const noteId = useId();
  const [note, setNote] = useState("");
  const [confirmSuspend, setConfirmSuspend] = useState(false);
  const name = group.target.nickname ?? t("someone");
  const decide = useMutation({
    mutationFn: (decision: "suspend" | "dismiss") =>
      decidePlatformReport(token, group.reports[0].id, { decision, note: note.trim() || null }),
    onSuccess: (result) => {
      void queryClient.invalidateQueries({ queryKey: PLATFORM_REPORTS_KEY });
      onDone(
        result.decision === "suspend"
          ? t("reports.suspended", { name, sponsors: result.penalized_sponsors })
          : t("reports.dismissed", { name, count: result.resolved }),
      );
    },
  });
  const minor = group.reports.some((report) => report.reason === "minor");

  return (
    <article className="flex min-w-0 flex-col gap-3 border border-[var(--border)] bg-[var(--panel)] p-4" data-testid={`report-group-${group.target.id}`}>
      <div className="flex min-w-0 flex-wrap items-center gap-3">
        <PersonAvatar name={group.target.nickname} url={group.target.avatar_url} size={40} />
        <div className="min-w-0 flex-1">
          <p className="truncate text-base font-semibold text-[var(--text)]">{name}</p>
          <p className="text-xs text-[var(--text-soft)]">{t("reports.count", { count: group.reports.length })}</p>
        </div>
        {minor ? (
          <span className="border border-[var(--border)] bg-[var(--panel-muted)] px-2 py-0.5 text-xs font-semibold text-[var(--warning)]">{t("reason.minor")}</span>
        ) : null}
      </div>
      <ul className="flex flex-col gap-2">
        {group.reports.map((report) => (
          <li key={report.id} className="flex min-w-0 flex-col gap-0.5 border-t border-[var(--border)] pt-2 text-sm">
            <span className="font-semibold text-[var(--text)]">{t(`reason.${report.reason}`)}</span>
            <span className="text-xs text-[var(--text-soft)]">
              {t("reports.by", {
                name: report.reporter.nickname ?? t("someone"),
                date: format.dateTime(new Date(report.created_at), withClock(locale, { dateStyle: "medium", timeStyle: "short" })),
              })}
            </span>
            {report.note ? <span className="break-words text-[var(--text)]">{report.note}</span> : null}
          </li>
        ))}
      </ul>
      <label htmlFor={noteId} className="text-xs font-semibold text-[var(--text-soft)]">{t("reports.note")}</label>
      <textarea
        id={noteId}
        className="min-h-16 w-full border border-[var(--border)] bg-[var(--panel)] p-3 text-sm text-[var(--text)]"
        value={note}
        maxLength={DECISION_TEXT_MAX}
        onChange={(event) => setNote(event.target.value)}
      />
      {decide.error ? <ReportError error={decide.error} /> : null}
      {confirmSuspend ? (
        <div className="flex flex-col gap-2 border border-[var(--border)] bg-[var(--panel-muted)] p-3" role="group" aria-label={t("reports.suspend")}>
          <p className="text-sm text-[var(--text)]">{t("reports.suspendConfirm", { name })}</p>
          <div className="flex flex-wrap gap-2">
            <button type="button" className={`${buttonClass} bg-[var(--danger)] text-[var(--danger-contrast)]`} disabled={decide.isPending} onClick={() => decide.mutate("suspend")}>
              {t("reports.suspendYes")}
            </button>
            <button type="button" className={`${buttonClass} border border-[var(--border)] text-[var(--text-soft)]`} disabled={decide.isPending} onClick={() => setConfirmSuspend(false)}>
              {t("cancel")}
            </button>
          </div>
        </div>
      ) : (
        <div className="flex flex-wrap gap-2">
          <button type="button" className={`${buttonClass} bg-[var(--danger)] text-[var(--danger-contrast)]`} disabled={decide.isPending} onClick={() => setConfirmSuspend(true)}>
            {t("reports.suspend")}
          </button>
          <button type="button" className={`${buttonClass} border border-[var(--border)] text-[var(--text)]`} disabled={decide.isPending} onClick={() => decide.mutate("dismiss")}>
            {t("reports.dismiss")}
          </button>
        </div>
      )}
    </article>
  );
}

function ReportError({ error }: { error: unknown }) {
  const t = useTranslations("PlatformPartners");
  if (error instanceof ApiError && error.payload.code === "partner_report_decided") {
    return <ErrorNotice>{t("reports.alreadyDecided")}</ErrorNotice>;
  }
  return <VerifyError error={error} />;
}

/** «Ποιότητα προτάσεων»: the last 30 days' anonymous counters of «Κλείστε μαζί». */
function SuggestionStatsCard({ token }: { token: string }) {
  const t = useTranslations("PlatformPartners");
  const format = useFormatter();
  const stats = useQuery({ queryKey: SUGGESTION_STATS_KEY, queryFn: () => fetchSuggestionStats(token) });
  if (!stats.data) return null;
  const totals = suggestionTotals(stats.data);
  const reasons = stats.data.feedback_reasons;
  const tiles: { key: string; value: string }[] = [
    { key: "shown", value: format.number(totals.shown) },
    { key: "proposed", value: format.number(totals.proposed) },
    { key: "proposedShare", value: totals.proposedShare === null ? "—" : `${format.number(totals.proposedShare)}%` },
    { key: "feedback", value: format.number(totals.feedback) },
  ];
  return (
    <section className="mt-10 flex flex-col gap-3 border border-[var(--border)] bg-[var(--panel)] p-4" aria-label={t("stats.title")} data-testid="suggestion-stats">
      <div>
        <h2 className="text-lg font-semibold text-[var(--text)]">{t("stats.title")}</h2>
        <p className="text-xs text-[var(--text-soft)]">
          {t("stats.since", { date: format.dateTime(dateAtNoon(stats.data.since), { dateStyle: "medium" }) })}
        </p>
      </div>
      <dl className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {tiles.map((tile) => (
          <div key={tile.key} className="min-w-0">
            <dt className="text-xs text-[var(--text-soft)]">{t(`stats.${tile.key}`)}</dt>
            <dd className="text-2xl font-semibold tabular-nums text-[var(--text)]">{tile.value}</dd>
          </div>
        ))}
      </dl>
      <div>
        <p className="text-xs font-bold uppercase tracking-[0.16em] text-[var(--dim)]">{t("stats.reasons")}</p>
        <ul className="mt-1 flex flex-wrap gap-x-4 gap-y-1 text-sm text-[var(--text)]">
          {(["not_near", "bad_time", "wrong_level", "other"] as const).map((key) => (
            <li key={key}>
              {t(`stats.reason.${key}`)}: <span className="tabular-nums">{format.number(reasons[key])}</span>
            </li>
          ))}
        </ul>
      </div>
      <p className="text-xs text-[var(--dim)]">{t("stats.note")}</p>
    </section>
  );
}
