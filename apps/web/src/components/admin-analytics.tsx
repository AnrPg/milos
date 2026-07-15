"use client";

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

function formatCount(value: number) {
  return new Intl.NumberFormat("en-US").format(value);
}

function formatMoney(cents: number) {
  return new Intl.NumberFormat("en-US", {
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
}: {
  label: string;
  value: string;
  helper?: string;
}) {
  return (
    <div className="rounded-[1.5rem] border border-[color:var(--border)] bg-[var(--panel)] p-5">
      <p className="text-xs font-bold uppercase tracking-[0.18em] text-[var(--muted)]">{label}</p>
      <p className="mt-3 text-3xl font-black">{value}</p>
      {helper ? <p className="mt-2 text-xs leading-5 text-[var(--muted)]">{helper}</p> : null}
    </div>
  );
}

function BreakdownList({ title, rows }: { title: string; rows: [string, unknown][] }) {
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
                <span className="font-bold text-[var(--text)]">{formatCount(value)}</span>
              </div>
              <div className="mt-2 h-2 rounded-full bg-[var(--panel-muted)]">
                <div
                  className="h-2 rounded-full bg-[var(--success)]"
                  style={{ width: `${Math.max((value / max) * 100, value > 0 ? 8 : 0)}%` }}
                />
              </div>
            </div>
          ))}
        </div>
      ) : (
        <p className="mt-4 text-sm text-[var(--muted)]">No captured facts in this reporting window.</p>
      )}
    </article>
  );
}

export function AdminAnalytics() {
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

  return (
    <main className="min-h-screen bg-[var(--bg)] px-6 py-10 text-[var(--text)] md:px-10">
      <div className="mx-auto max-w-6xl space-y-8">
        <TransientHero label="analytics introduction">
        <section className="rounded-[2rem] border border-[color:var(--border)] bg-[var(--panel)] p-5">
          <p className="text-xs font-bold uppercase tracking-[0.24em] text-[var(--primary)]">Analytics &amp; Marketing</p>
          <h1 className="mt-2 text-3xl font-black tracking-tight md:text-4xl">Analytics &amp; Marketing</h1>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-[var(--muted)]">
            Review finance, coaching, feedback, wellbeing, attendance, communication, and notification engagement from
            persisted facts. Empty values mean no matching facts were captured in the selected window.
          </p>
          <Link
            className="mt-5 inline-flex rounded-full px-4 py-2 text-sm font-semibold"
            href="/admin/metrics"
            style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}
          >
            ← Analytics &amp; Marketing
          </Link>
        </section>
        </TransientHero>

        {summaryQuery.error instanceof Error ? (
          <p className="rounded-2xl border border-[color:var(--danger)] bg-[color-mix(in_srgb,var(--danger)_15%,transparent)] p-4 text-sm text-[var(--danger)]">
            {summaryQuery.error.message}
          </p>
        ) : null}

        <section className="grid gap-4 md:grid-cols-4">
          <KpiCard
            label="Paid revenue"
            value={formatMoney(metricNumber(financeTotals, "paid_revenue_cents"))}
            helper={`${formatCount(metricNumber(dashboardFinance, "active_memberships"))} active memberships`}
          />
          <KpiCard label="Reviews" value={formatCount(metricNumber(feedback, "total"))} />
          <KpiCard
            label="Active injuries"
            value={formatCount(metricNumber(wellbeing, "active_count"))}
            helper={`${formatCount(metricNumber(wellbeing, "total"))} total reports`}
          />
          <KpiCard
            label="Notification clicks"
            value={formatCount(metricNumber(notificationClicks, "total"))}
            helper={`${formatCount(metricNumber(events, "total"))} tracked events`}
          />
        </section>

        <section id="training-analytics" className="scroll-mt-20 rounded-[1.6rem] border border-[color:var(--border)] bg-[var(--panel)] p-6">
          <h2 className="text-xl font-black">Team workout breakdown (last 30 days)</h2>
          <div className="mt-4 grid gap-4 md:grid-cols-3">
            <KpiCard label="Team completions" value={formatCount(metricNumber(teamWorkoutsAggregate, "team_count"))} />
            <KpiCard
              label="Individual completions"
              value={formatCount(metricNumber(teamWorkoutsAggregate, "individual_count"))}
            />
            <KpiCard label="Total completions" value={formatCount(metricNumber(teamWorkoutsAggregate, "total_count"))} />
          </div>
          {Object.keys(teamWorkoutsByUser).length > 0 ? (
            <div className="mt-6 overflow-hidden rounded-2xl border border-[color:var(--border)]">
              <p className="mb-2 text-xs font-bold uppercase tracking-[0.16em] text-[var(--muted)]">Per user</p>
              <table className="w-full text-left text-sm">
                <tbody>
                  {entries(teamWorkoutsByUser).slice(0, 8).map(([userId, count]) => (
                    <tr key={userId} className="border-t border-[color:var(--border)]">
                      <td className="p-3 font-mono text-xs text-[var(--muted)]">{userId}</td>
                      <td className="p-3 text-right font-bold">{formatCount(Number(count))}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : null}
          <div className="mt-6">
            <BreakdownList title="Attendance" rows={entries(asRecord(attendance.by_status))} />
          </div>
        </section>

        <section id="user-engagement" className="scroll-mt-20 grid gap-4 lg:grid-cols-2">
          <div className="lg:col-span-2">
            <p className="text-xs font-bold uppercase tracking-[0.2em] text-[var(--primary)]">User Engagement</p>
            <h2 className="mt-2 text-xl font-black">Interaction and communication signals</h2>
          </div>
          <BreakdownList title="Event mix" rows={entries(asRecord(events.by_name))} />
          <BreakdownList title="Push delivery" rows={entries(asRecord(pushDispatch.by_status))} />
          <BreakdownList title="Communication" rows={entries(asRecord(communication.by_direction))} />
          <BreakdownList title="Review ratings" rows={entries(reviewByRating)} />
        </section>

        <section id="coaching-analytics" className="scroll-mt-20 rounded-[1.6rem] border border-[color:var(--border)] bg-[var(--panel)] p-6">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div>
              <p className="text-xs font-bold uppercase tracking-[0.2em] text-[var(--primary)]">Coaching Analytics</p>
              <h2 className="mt-2 text-xl font-black">Athlete activity and follow-up</h2>
            </div>
            <Link className="text-sm font-bold text-[var(--primary)]" href="/admin/coaching-assignments">
              Open Personal Coaching →
            </Link>
          </div>
          <div className="mt-5 grid gap-4 md:grid-cols-3">
            <KpiCard label="Active athletes" value={formatCount(metricNumber(coaching, "active_athletes"))} />
            <KpiCard label="Captured events" value={formatCount(metricNumber(dashboardCoaching, "event_count"))} />
            <KpiCard label="Reviews" value={formatCount(metricNumber(dashboardCoaching, "review_count"))} />
          </div>
        </section>

        <section id="health-incidents" className="scroll-mt-20 rounded-[1.6rem] border border-[color:var(--border)] bg-[var(--panel)] p-6">
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div>
              <p className="text-xs font-bold uppercase tracking-[0.2em] text-[var(--primary)]">Health / Incidents</p>
              <h2 className="mt-2 text-xl font-black">Injury and limitation signals</h2>
            </div>
            <Link className="text-sm font-bold text-[var(--primary)]" href="/admin/wellbeing">
              Open incident records →
            </Link>
          </div>
          <div className="mt-5 grid gap-4 md:grid-cols-3">
            <KpiCard label="Active injuries" value={formatCount(metricNumber(wellbeing, "active_count"))} />
            <KpiCard label="Total reports" value={formatCount(metricNumber(wellbeing, "total"))} />
            <KpiCard label="Recent injury flags" value={formatCount(metricNumber(dashboardCoaching, "injury_count"))} />
          </div>
        </section>

        <section className="grid gap-4 lg:grid-cols-2">
          <article className="rounded-[1.6rem] border border-[color:var(--border)] bg-[var(--panel)] p-6">
            <h2 className="text-xl font-black">Operational status</h2>
            <dl className="mt-5 space-y-4 text-sm">
              <div className="flex justify-between gap-4">
                <dt className="text-[var(--muted)]">Finance aggregate</dt>
                <dd className="font-bold capitalize">{metricText(dashboardFinance, "aggregate_status")}</dd>
              </div>
              <div className="flex justify-between gap-4">
                <dt className="text-[var(--muted)]">Low-rating reviews</dt>
                <dd className="font-bold">{formatCount(metricNumber(crossContext, "low_rating_count"))}</dd>
              </div>
              <div className="flex justify-between gap-4">
                <dt className="text-[var(--muted)]">Expiring memberships</dt>
                <dd className="font-bold">{formatCount(metricNumber(dashboardFinance, "expiring_memberships"))}</dd>
              </div>
              <div className="flex justify-between gap-4">
                <dt className="text-[var(--muted)]">Coaching active athletes</dt>
                <dd className="font-bold">{formatCount(metricNumber(coaching, "active_athletes"))}</dd>
              </div>
            </dl>
          </article>
        </section>
      </div>
    </main>
  );
}
