"use client";







import {useUiLocale} from "@/i18n/use-ui-locale";
import {useUiTranslations} from "@/i18n/ui";
import { useQuery } from "@tanstack/react-query";
import Link from "next/link";

import { fetchAdminAnalyticsSummary } from "@/api/analytics";
import { useSession } from "@/components/session-provider";
import { TransientHero } from "@/components/TransientHero";

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" ? (value as Record<string, unknown>) : {};
}

function metricNumber(record: Record<string, unknown>, key: string) {
  const value = record[key];
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function metricText(record: Record<string, unknown>, key: string) {
  const value = record[key];
  return typeof value === "string" && value.length > 0 ? value : "unknown";
}

function formatCount(uiLocale: string, value: number) {
  return new Intl.NumberFormat(uiLocale).format(value);
}

function formatMoney(uiLocale: string, cents: number) {
  return new Intl.NumberFormat(uiLocale, {
    style: "currency",
    currency: "EUR",
    maximumFractionDigits: 0,
  }).format(cents / 100);
}

function entries(record: Record<string, unknown>) {
  return Object.entries(record)
    .filter(([, value]) => typeof value === "number" && Number.isFinite(value))
    .sort((left, right) => Number(right[1]) - Number(left[1]));
}

function KpiCard({
  label,
  value,
  helper,
  href,
}: {
  label: string;
  value: string;
  helper?: string;
  href?: string;
}) {
  const content = (
    <>
      <p className="text-xs font-bold uppercase tracking-[0.18em] text-[var(--muted)]">{label}</p>
      <p className="mt-3 text-3xl font-black">{value}</p>
      {helper ? <p className="mt-2 text-xs leading-5 text-[var(--muted)]">{helper}</p> : null}
    </>
  );

  return href ? (
    <Link href={href} className="rounded-[1.5rem] border border-[color:var(--border)] bg-[var(--panel)] p-5 transition-transform hover:-translate-y-0.5">
      {content}
    </Link>
  ) : (
    <div className="rounded-[1.5rem] border border-[color:var(--border)] bg-[var(--panel)] p-5">
      {content}
    </div>
  );
}

function BreakdownList({ title, rows }: { title: string; rows: [string, unknown][] }) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const numericRows = rows.filter(([, value]) => typeof value === "number") as [string, number][];
  const max = Math.max(...numericRows.map(([, value]) => value), 1);

  return (
    <article className="rounded-[1.6rem] border border-[color:var(--border)] bg-[var(--panel)] p-6">
      <h2 className="text-xl font-black">{title}</h2>
      {numericRows.length > 0 ? (
        <div className="mt-5 space-y-4">
          {numericRows.map(([label, value]) => (
            <div key={label}>
              <div className="flex items-center justify-between gap-3 text-sm">
                <span className="capitalize text-[var(--text-soft)]">{label.replaceAll("_", " ")}</span>
                <span className="font-bold text-[var(--text)]">{formatCount(uiLocale, value)}</span>
              </div>
              <div className="mt-2 h-2 rounded-full bg-[var(--panel-muted)]">
                <div
                  className="h-2 rounded-full bg-[var(--success)]"
                  style={{ width: (Math.max((value / max) * 100, value > 0 ? 8 : 0)) + "%" }}
                />
              </div>
            </div>
          ))}
        </div>
      ) : (
        <p className="mt-4 text-sm text-[var(--muted)]">{i18n("noCapturedFactsInThisReportingWindowdc344c7")}</p>
      )}
    </article>
  );
}

type AnalyticsSection = "overview" | "training" | "coaching" | "engagement" | "health";

export function AdminAnalytics({ section = "overview" }: { section?: AnalyticsSection }) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const SECTION_COPY: Record<AnalyticsSection, { eyebrow: string; title: string; body: string }> = {
    overview: {
      eyebrow: i18n("analyticsMarketinga05588a"),
      title: i18n("overview0efc2e6"),
      body: i18n("crossDomainSignalsFromPersistedFactsEmptyValues1643637"),
    },
    training: {
      eyebrow: i18n("trainingAnalytics2c25dde"),
      title: i18n("trainingPerformancea32baa9"),
      body: i18n("attendanceCompletionsWorkoutTypeAndTeamWorkoutTrendscbfd912"),
    },
    coaching: {
      eyebrow: i18n("coachingAnalyticsb6ddda1"),
      title: i18n("athleteActivityAndFollowUp5a9fe9c"),
      body: i18n("coachingActivityAdherenceSignalsAssignmentCompletionReviewsAnd09689b3"),
    },
    engagement: {
      eyebrow: i18n("userEngagement72f61cf"),
      title: i18n("interactionSignalsff55586"),
      body: i18n("reviewsCommunicationNotificationDeliveryClicksAndOtherInteraction6acad47"),
    },
    health: {
      eyebrow: i18n("healthIncidentsb8da1fe"),
      title: i18n("injuryAndLimitationSignalsfc3b586"),
      body: i18n("aggregateInjuryLimitationSeverityActiveReportsAndUnresolvedc765d16"),
    },
  };
  const { tokens } = useSession();

  const summaryQuery = useQuery({
    queryKey: ["admin", "analytics", "summary"],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => fetchAdminAnalyticsSummary(tokens!.access_token, 30),
  });

  const payload = asRecord(summaryQuery.data);
  const analytics = asRecord(payload.analytics);
  const events = asRecord(analytics.events);
  const teamWorkouts = asRecord(analytics.team_workouts);
  const teamWorkoutsAggregate = asRecord(teamWorkouts.aggregate);
  const teamWorkoutsByUser = asRecord(teamWorkouts.by_user);
  const feedback = asRecord(payload.feedback);
  const wellbeing = asRecord(payload.wellbeing);
  const finance = asRecord(payload.finance);
  const coaching = asRecord(payload.coaching);
  const dashboard = asRecord(payload.dashboard);
  const crossContext = asRecord(dashboard.cross_context);
  const dashboardFinance = asRecord(dashboard.finance);
  const dashboardCoaching = asRecord(dashboard.coaching);
  const financeTotals = asRecord(finance.totals);
  const pushDispatch = asRecord(analytics.push_dispatch);
  const attendance = asRecord(analytics.attendance);
  const communication = asRecord(analytics.communication);
  const notificationClicks = asRecord(analytics.notification_clicks);
  const reviewByRating = asRecord(feedback.by_rating);
  const copy = SECTION_COPY[section];

  return (
    <main className="min-h-screen bg-[var(--bg)] px-6 py-10 text-[var(--text)] md:px-10">
      <div className="mx-auto max-w-6xl space-y-8">
        <TransientHero collapsedTitle={copy.eyebrow} label={i18n("analyticsIntroductiond80c96b")} timeoutMs={3000}>
        <section className="rounded-[2rem] border border-[color:var(--border)] bg-[var(--panel)] p-5">
          <p className="text-xs font-bold uppercase tracking-[0.24em] text-[var(--primary)]">{copy.eyebrow}</p>
          <h1 className="mt-2 text-3xl font-black tracking-tight md:text-4xl">{copy.title}</h1>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-[var(--muted)]">
            {copy.body}
          </p>
          <Link
            className="mt-5 inline-flex rounded-full px-4 py-2 text-sm font-semibold"
            href="/admin/metrics"
            style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}
          >
            {i18n("analyticsMarketing0ecf7f0")}
          </Link>
        </section>
        </TransientHero>

        {summaryQuery.error instanceof Error ? (
          <p className="rounded-2xl border border-[color:var(--danger)] bg-[color-mix(in_srgb,var(--danger)_15%,transparent)] p-4 text-sm text-[var(--danger)]">
            {summaryQuery.error.message}
          </p>
        ) : null}

        {section === "overview" ? <section className="grid gap-4 md:grid-cols-4">
          <KpiCard
            label={i18n("paidRevenue64c34e5")}
            value={formatMoney(uiLocale, metricNumber(financeTotals, "paid_revenue_cents"))}
            helper={(formatCount(uiLocale, metricNumber(dashboardFinance, "active_memberships"))) + i18n("activeMemberships6d55ee8")}
            href="/admin/metrics/finance"
          />
          <KpiCard label={i18n("reviewsb83c4cd")} value={formatCount(uiLocale, metricNumber(feedback, "total"))} href="/admin/reviews" />
          <KpiCard
            label={i18n("activeInjuriesdaecfa6")}
            value={formatCount(uiLocale, metricNumber(wellbeing, "active_count"))}
            helper={(formatCount(uiLocale, metricNumber(wellbeing, "total"))) + i18n("totalReportsdfd4b9e")}
            href="/admin/metrics/health"
          />
          <KpiCard
            label={i18n("notificationClicks02c5775")}
            value={formatCount(uiLocale, metricNumber(notificationClicks, "total"))}
            helper={(formatCount(uiLocale, metricNumber(events, "total"))) + i18n("trackedEvents398d5c2")}
            href="/admin/metrics/engagement"
          />
        </section> : null}

        {section === "training" ? <section id="training-analytics" className="scroll-mt-20 rounded-[1.6rem] border border-[color:var(--border)] bg-[var(--panel)] p-6">
          <h2 className="text-xl font-black">{i18n("teamWorkoutBreakdownLast30Days86ec3d2")}</h2>
          <div className="mt-4 grid gap-4 md:grid-cols-3">
            <KpiCard label={i18n("teamCompletions2a732d2")} value={formatCount(uiLocale, metricNumber(teamWorkoutsAggregate, "team_count"))} />
            <KpiCard
              label={i18n("individualCompletions70ee9b2")}
              value={formatCount(uiLocale, metricNumber(teamWorkoutsAggregate, "individual_count"))}
            />
            <KpiCard label={i18n("totalCompletionsfa16f4c")} value={formatCount(uiLocale, metricNumber(teamWorkoutsAggregate, "total_count"))} />
          </div>
          {Object.keys(teamWorkoutsByUser).length > 0 ? (
            <div className="mt-6 overflow-hidden rounded-2xl border border-[color:var(--border)]">
              <p className="mb-2 text-xs font-bold uppercase tracking-[0.16em] text-[var(--muted)]">{i18n("perUser3fcfda7")}</p>
              <table className="w-full text-start text-sm">
                <tbody>
                  {entries(teamWorkoutsByUser).slice(0, 8).map(([userId, count]) => (
                    <tr key={userId} className="border-t border-[color:var(--border)]">
                      <td className="p-3 font-mono text-xs text-[var(--muted)]">{userId}</td>
                      <td className="p-3 text-end font-bold">{formatCount(uiLocale, Number(count))}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : null}
          <div className="mt-6">
            <BreakdownList title={i18n("attendanceb689313")} rows={entries(asRecord(attendance.by_status))} />
          </div>
        </section> : null}

        {section === "engagement" ? <section id="user-engagement" className="scroll-mt-20 grid gap-4 lg:grid-cols-2">
          <div className="lg:col-span-2">
            <p className="text-xs font-bold uppercase tracking-[0.2em] text-[var(--primary)]">{i18n("userEngagement72f61cf")}</p>
            <h2 className="mt-2 text-xl font-black">{i18n("interactionAndCommunicationSignals18b657a")}</h2>
          </div>
          <BreakdownList title={i18n("eventMix09a541e")} rows={entries(asRecord(events.by_name))} />
          <BreakdownList title={i18n("pushDelivery52c03a7")} rows={entries(asRecord(pushDispatch.by_status))} />
          <BreakdownList title={i18n("communicationade0d50")} rows={entries(asRecord(communication.by_direction))} />
          <BreakdownList title={i18n("reviewRatingsd575ce1")} rows={entries(reviewByRating)} />
        </section> : null}

        {section === "coaching" ? <section id="coaching-analytics" className="scroll-mt-20 rounded-[1.6rem] border border-[color:var(--border)] bg-[var(--panel)] p-6">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div>
              <p className="text-xs font-bold uppercase tracking-[0.2em] text-[var(--primary)]">{i18n("coachingAnalyticsb6ddda1")}</p>
              <h2 className="mt-2 text-xl font-black">{i18n("athleteActivityAndFollowUp5a9fe9c")}</h2>
            </div>
            <Link className="text-sm font-bold text-[var(--primary)]" href="/admin/coaching-assignments">
              {i18n("openPersonalCoachingf4be893")}
            </Link>
          </div>
          <div className="mt-5 grid gap-4 md:grid-cols-3">
            <KpiCard label={i18n("activeAthletes78e231e")} value={formatCount(uiLocale, metricNumber(coaching, "active_athletes"))} />
            <KpiCard label={i18n("capturedEvents2551a14")} value={formatCount(uiLocale, metricNumber(dashboardCoaching, "event_count"))} />
            <KpiCard label={i18n("reviewsb83c4cd")} value={formatCount(uiLocale, metricNumber(dashboardCoaching, "review_count"))} />
          </div>
        </section> : null}

        {section === "health" ? <section id="health-incidents" className="scroll-mt-20 rounded-[1.6rem] border border-[color:var(--border)] bg-[var(--panel)] p-6">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div>
              <p className="text-xs font-bold uppercase tracking-[0.2em] text-[var(--primary)]">{i18n("healthIncidentsb8da1fe")}</p>
              <h2 className="mt-2 text-xl font-black">{i18n("injuryAndLimitationSignalsfc3b586")}</h2>
            </div>
            <Link className="text-sm font-bold text-[var(--primary)]" href="/admin/wellbeing">
              {i18n("openIncidentRecords7447df1")}
            </Link>
          </div>
          <div className="mt-5 grid gap-4 md:grid-cols-3">
            <KpiCard label={i18n("activeInjuriesdaecfa6")} value={formatCount(uiLocale, metricNumber(wellbeing, "active_count"))} />
            <KpiCard label={i18n("totalReports5654449")} value={formatCount(uiLocale, metricNumber(wellbeing, "total"))} />
            <KpiCard label={i18n("recentInjuryFlags0692c0a")} value={formatCount(uiLocale, metricNumber(dashboardCoaching, "injury_count"))} />
          </div>
        </section> : null}

        {section === "overview" ? <section className="grid gap-4 lg:grid-cols-2">
          <article className="rounded-[1.6rem] border border-[color:var(--border)] bg-[var(--panel)] p-6">
            <h2 className="text-xl font-black">{i18n("operationalStatus1fdea4e")}</h2>
            <dl className="mt-5 space-y-4 text-sm">
              <div className="flex justify-between gap-4">
                <dt className="text-[var(--muted)]">{i18n("financeAggregated28a516")}</dt>
                <dd className="font-bold capitalize">{metricText(dashboardFinance, "aggregate_status")}</dd>
              </div>
              <div className="flex justify-between gap-4">
                <dt className="text-[var(--muted)]">{i18n("lowRatingReviews928d645")}</dt>
                <dd className="font-bold">{formatCount(uiLocale, metricNumber(crossContext, "low_rating_count"))}</dd>
              </div>
              <div className="flex justify-between gap-4">
                <dt className="text-[var(--muted)]">{i18n("expiringMemberships522e6a4")}</dt>
                <dd className="font-bold">{formatCount(uiLocale, metricNumber(dashboardFinance, "expiring_memberships"))}</dd>
              </div>
              <div className="flex justify-between gap-4">
                <dt className="text-[var(--muted)]">{i18n("coachingActiveAthletese8bc87a")}</dt>
                <dd className="font-bold">{formatCount(uiLocale, metricNumber(coaching, "active_athletes"))}</dd>
              </div>
            </dl>
          </article>
        </section> : null}
      </div>
    </main>
  );
}
