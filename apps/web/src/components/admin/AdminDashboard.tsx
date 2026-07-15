"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";

import { type AdminChallengeRecord, fetchAdminChallenges } from "@/api/challenges";
import { fetchAdminAnalyticsSummary } from "@/api/analytics";
import { fetchFinanceQueues, fetchFinanceSummary, type FinanceRecord } from "@/api/finance";
import { fetchLandingPayload, type AdminMetrics } from "@/api/landing";
import { fetchSchedule } from "@/api/schedule";
import { useSession } from "@/components/session-provider";

type AlertCategory = "finance" | "coaching" | "training";

const DEFAULT_CATEGORIES: AlertCategory[] = ["finance", "coaching", "training"];
const STORAGE_KEY = "milos-admin-alert-categories";

function loadCategories(): AlertCategory[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return DEFAULT_CATEGORIES;
    const parsed = JSON.parse(raw) as unknown;
    if (Array.isArray(parsed)) return parsed as AlertCategory[];
  } catch {}
  return DEFAULT_CATEGORIES;
}

function saveCategories(cats: AlertCategory[]) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(cats));
  } catch {}
}

function money(cents: unknown) {
  const amount = typeof cents === "number" ? cents : Number(cents ?? 0);
  return new Intl.NumberFormat("en-GB", { style: "currency", currency: "EUR" }).format(amount / 100);
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

function isActiveChallenge(c: AdminChallengeRecord) {
  const now = Date.now();
  return new Date(c.starts_at).getTime() <= now && new Date(c.ends_at).getTime() >= now;
}

const NAV_GROUPS: Array<{ label: string; items: Array<{ label: string; href: string }> }> = [
  {
    label: "Programme",
    items: [
      { label: "Workouts", href: "/admin/workouts" },
      { label: "Class Schedule", href: "/admin/class-schedule" },
      { label: "Coaching Assignments", href: "/admin/coaching-assignments" },
      { label: "Challenges", href: "/admin/challenges" },
    ],
  },
  {
    label: "Revenue",
    items: [
      { label: "Finance Dashboard", href: "/admin/finance" },
      { label: "Finance Operations", href: "/admin/finance/operations" },
    ],
  },
  {
    label: "Analytics",
    items: [
      { label: "Metrics", href: "/admin/metrics" },
      { label: "Reviews", href: "/admin/reviews" },
      { label: "Wellbeing", href: "/admin/wellbeing" },
    ],
  },
  {
    label: "Settings",
    items: [
      { label: "Settings", href: "/admin/settings" },
    ],
  },
];

function AdminMetricChip({ label, value, href, danger = false, loading = false }: {
  label: string;
  value: string;
  href: string;
  danger?: boolean;
  loading?: boolean;
}) {
  return (
    <Link
      href={href}
      className="flex flex-col rounded-[1.9rem] p-5 transition-transform hover:-translate-y-0.5"
      style={{
        background: "var(--panel)",
        border: `1px solid ${danger ? "color-mix(in srgb, var(--danger, var(--primary)) 30%, transparent)" : "var(--border)"}`,
      }}
    >
      <span className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{label}</span>
      <span
        className="mt-3 text-3xl font-semibold tracking-tight"
        style={{ color: loading ? "var(--border)" : danger ? "var(--danger, var(--primary))" : "var(--text)" }}
      >
        {loading ? "…" : value}
      </span>
    </Link>
  );
}

function AdminChallengeCard({ challenge }: { challenge: AdminChallengeRecord }) {
  const pct = Math.round(challenge.progress_summary.completion_rate * 100);
  return (
    <article
      className="rounded-[1.6rem] p-5"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{challenge.title}</p>
          {challenge.description && (
            <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{challenge.description}</p>
          )}
          <p className="mt-1.5 text-xs" style={{ color: "var(--muted)" }}>
            {formatDate(challenge.starts_at)} – {formatDate(challenge.ends_at)}
          </p>
        </div>
        <span
          className="shrink-0 rounded-full px-2 py-1 text-[10px] font-semibold"
          style={{ background: "color-mix(in srgb, var(--primary) 12%, transparent)", color: "var(--primary)" }}
        >
          {challenge.badge_label}
        </span>
      </div>

      <div className="mt-4 h-1.5 overflow-hidden rounded-full" style={{ background: "var(--border)" }}>
        <div
          className="h-full rounded-full"
          style={{ width: `${pct}%`, background: pct === 100 ? "var(--success)" : "var(--primary)" }}
        />
      </div>

      <div className="mt-3 flex gap-4 text-xs" style={{ color: "var(--muted)" }}>
        <span>{challenge.progress_summary.participants} participants</span>
        <span>{challenge.progress_summary.completed} completed</span>
        <span>{pct}% completion rate</span>
      </div>
    </article>
  );
}

export function AdminDashboard() {
  const { currentUser, signOut, tokens } = useSession();
  const [configOpen, setConfigOpen] = useState(false);
  const [activeCategories, setActiveCategories] = useState<AlertCategory[]>(DEFAULT_CATEGORIES);

  useEffect(() => {
    queueMicrotask(() => setActiveCategories(loadCategories()));
  }, []);

  const token = tokens?.access_token;
  const enabled = Boolean(token);

  const financeQuery = useQuery({
    queryKey: ["admin", "dashboard", "finance-summary"],
    enabled,
    queryFn: () => fetchFinanceSummary(token!),
  });

  const queuesQuery = useQuery({
    queryKey: ["admin", "dashboard", "queues"],
    enabled,
    queryFn: () => fetchFinanceQueues(token!, { expires_within_days: "30" }),
  });

  const analyticsQuery = useQuery({
    queryKey: ["admin", "dashboard", "analytics"],
    enabled,
    queryFn: () => fetchAdminAnalyticsSummary(token!),
  });

  const scheduleQuery = useQuery({
    queryKey: ["admin", "dashboard", "schedule"],
    enabled,
    queryFn: () => {
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      const endDate = new Date(today);
      endDate.setDate(today.getDate() + 7);
      return fetchSchedule(token!, {
        startAt: today.toISOString(),
        endAt: endDate.toISOString(),
        days: 7,
        trainingType: null,
      });
    },
  });

  const landingQuery = useQuery({
    queryKey: ["admin", "dashboard", "landing"],
    enabled,
    queryFn: () => fetchLandingPayload(token!),
    staleTime: 2 * 60 * 1000,
  });

  const challengesQuery = useQuery({
    queryKey: ["admin", "dashboard", "challenges"],
    enabled,
    queryFn: () => fetchAdminChallenges(token!),
    staleTime: 5 * 60 * 1000,
  });

  const totals = (financeQuery.data?.totals ?? {}) as FinanceRecord;
  const queues = (queuesQuery.data?.queues ?? {}) as Record<string, FinanceRecord[]>;
  const coaching = ((analyticsQuery.data as FinanceRecord)?.coaching ?? {}) as FinanceRecord;
  const slots = scheduleQuery.data?.slots ?? [];
  const adminMetrics = (landingQuery.data?.admin_metrics ?? null) as AdminMetrics | null;
  const activeChallenges = (challengesQuery.data?.challenges ?? []).filter(isActiveChallenge);

  const pendingBookingsCount = slots.reduce(
    (sum, slot) => sum + (slot.bookings ?? []).filter((b) => b.status === "pending").length,
    0,
  );

  const financeLoading = financeQuery.isLoading;
  const landingLoading = landingQuery.isLoading;

  // ── KPI rows ──────────────────────────────────────────────────────────────
  const financeKpis: Array<[string, string, boolean, string]> = [
    ["Active members", String(totals.active_memberships ?? 0), false, "/admin/finance"],
    ["Revenue MTD", money(totals.paid_revenue_cents), false, "/admin/finance"],
    ["Expiring ≤30d", String(totals.expiring_memberships ?? 0), Number(totals.expiring_memberships ?? 0) > 0, "/admin/finance/operations?tab=queues"],
    ["Overdue invoices", money(totals.overdue_invoice_balance_cents), Number(totals.overdue_invoice_balance_cents ?? 0) > 0, "/admin/finance/operations?tab=queues"],
  ];

  const operationalKpis: Array<[string, string, boolean, string]> = [
    ["Classes today", String(adminMetrics?.classes_today ?? 0), false, "/admin/class-schedule"],
    ["Pending approvals", String(adminMetrics?.pending_referral_approvals ?? 0), Number(adminMetrics?.pending_referral_approvals ?? 0) > 0, "/admin/finance/operations?tab=referrals"],
    ["Total outstanding", money(adminMetrics?.total_outstanding_cents ?? 0), Number(adminMetrics?.total_outstanding_cents ?? 0) > 0, "/admin/finance/operations"],
    ["Members", String(adminMetrics?.member_count ?? 0), false, "/admin/finance"],
  ];

  // ── Alerts ─────────────────────────────────────────────────────────────────
  const financeAlerts: Array<{ text: string; href: string }> = [
    ...(Number(totals.expiring_memberships ?? 0) > 0
      ? [{ text: `${String(totals.expiring_memberships)} memberships expiring within 30 days`, href: "/admin/finance/operations?tab=queues" }]
      : []),
    ...((queues.overdue_invoices ?? []).length > 0
      ? [{ text: `${String((queues.overdue_invoices ?? []).length)} overdue invoices`, href: "/admin/finance/operations?tab=queues" }]
      : []),
    ...((queues.pending_payments ?? []).length > 0
      ? [{ text: `${String((queues.pending_payments ?? []).length)} pending payments`, href: "/admin/finance/operations?tab=queues" }]
      : []),
    ...((queues.pending_referral_rewards ?? []).length > 0
      ? [{ text: `${String((queues.pending_referral_rewards ?? []).length)} pending referral rewards`, href: "/admin/finance/operations?tab=referrals" }]
      : []),
  ];

  const coachingAlerts: Array<{ text: string; href: string }> = [
    ...(Number(coaching.injury_count ?? 0) > 0
      ? [{ text: `${String(coaching.injury_count)} injury flags since last visit`, href: "/admin/wellbeing" }]
      : []),
    ...(Number(coaching.review_count ?? 0) > 0
      ? [{ text: `${String(coaching.review_count)} unread workout reviews`, href: "/admin/reviews" }]
      : []),
  ];

  const trainingAlerts: Array<{ text: string; href: string }> = [
    ...(pendingBookingsCount > 0
      ? [{ text: `${String(pendingBookingsCount)} pending booking approvals`, href: "/admin/class-schedule" }]
      : []),
  ];

  const allAlerts: Record<AlertCategory, { label: string; items: Array<{ text: string; href: string }> }> = {
    finance: { label: "Finance", items: financeAlerts },
    coaching: { label: "Coaching", items: coachingAlerts },
    training: { label: "Training", items: trainingAlerts },
  };

  const hasAnyAlert = activeCategories.some((cat) => allAlerts[cat].items.length > 0);

  function toggleCategory(cat: AlertCategory) {
    const next = activeCategories.includes(cat)
      ? activeCategories.filter((c) => c !== cat)
      : [...activeCategories, cat];
    setActiveCategories(next);
    saveCategories(next);
  }

  const hour = new Date().getHours();
  const greeting = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening";

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-6xl space-y-8">

        {/* Hero */}
        <section className="rounded-[2.6rem] p-8" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <div className="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>
                Admin
              </p>
              <h1 className="mt-4 text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "var(--text)" }}>
                {greeting}, {currentUser?.nickname}.
              </h1>
              <p className="mt-4 text-base leading-7" style={{ color: "var(--muted)" }}>
                {new Date().toLocaleDateString(undefined, { weekday: "long", year: "numeric", month: "long", day: "numeric" })}
              </p>
            </div>
            <div className="flex flex-wrap gap-3">
              <Link
                href="/admin/finance/operations"
                className="rounded-2xl px-5 py-3 text-sm font-semibold text-center"
                style={{ background: "var(--text)", color: "var(--bg)" }}
              >
                Finance Operations
              </Link>
              <Link
                href="/admin/class-schedule"
                className="rounded-2xl px-5 py-3 text-sm font-semibold text-center"
                style={{ background: "var(--border)", border: "1px solid var(--border-strong)", color: "var(--text-soft)" }}
              >
                Class Schedule
              </Link>
              <button
                className="rounded-2xl px-5 py-3 text-sm font-semibold"
                style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)", color: "var(--primary)" }}
                onClick={signOut}
                type="button"
              >
                Log out
              </button>
            </div>
          </div>
        </section>

        {/* Finance KPIs */}
        <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {financeKpis.map(([label, value, warn, href]) => (
            <AdminMetricChip key={label} label={label} value={value} href={href} danger={warn} loading={financeLoading} />
          ))}
        </section>

        {/* Operational KPIs (from landing/admin_metrics) */}
        <section className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {operationalKpis.map(([label, value, warn, href]) => (
            <AdminMetricChip key={label} label={label} value={value} href={href} danger={warn} loading={landingLoading} />
          ))}
        </section>

        {/* Seasonal Challenges */}
        <section className="rounded-[2.2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <div className="flex items-center justify-between gap-4">
            <div>
              <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>Seasonal Challenges</p>
              <h2 className="mt-2 text-xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>
                {activeChallenges.length === 0 && !challengesQuery.isLoading
                  ? "No active challenges"
                  : `${activeChallenges.length} active`}
              </h2>
            </div>
            <Link
              href="/admin/challenges"
              className="rounded-full px-4 py-2 text-sm font-semibold"
              style={{ background: "var(--border)", border: "1px solid var(--border-strong)", color: "var(--text-soft)" }}
            >
              Manage →
            </Link>
          </div>

          {challengesQuery.isLoading ? (
            <div className="mt-5 space-y-3">
              {[1, 2].map((i) => (
                <div key={i} className="h-24 animate-pulse rounded-[1.6rem]" style={{ background: "var(--border)" }} />
              ))}
            </div>
          ) : activeChallenges.length === 0 ? (
            <p className="mt-5 rounded-2xl px-4 py-5 text-sm" style={{ background: "var(--panel-muted)", color: "var(--dim)" }}>
              No active seasonal challenges. Create one to start tracking member progress.
            </p>
          ) : (
            <div className="mt-5 grid gap-3 sm:grid-cols-2">
              {activeChallenges.map((c) => (
                <AdminChallengeCard key={c.id} challenge={c} />
              ))}
            </div>
          )}
        </section>

        {/* Needs Attention */}
        <section className="rounded-[2.2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <div className="flex items-center justify-between gap-4">
            <div>
              <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>Needs attention</p>
              {!hasAnyAlert && !financeQuery.isLoading && (
                <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>No urgent items. All clear.</p>
              )}
            </div>
            <button
              className="rounded-full px-4 py-2 text-xs font-semibold"
              style={{ background: "var(--border)", color: "var(--text-soft)" }}
              onClick={() => setConfigOpen((v) => !v)}
              type="button"
            >
              {configOpen ? "Done" : "Configure ✦"}
            </button>
          </div>

          {configOpen && (
            <div className="mt-4 flex flex-wrap gap-3 rounded-[1.4rem] p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
              <p className="w-full text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                Show alert categories
              </p>
              {(["finance", "coaching", "training"] as AlertCategory[]).map((cat) => (
                <button
                  key={cat}
                  className="rounded-full px-4 py-2 text-sm font-semibold capitalize"
                  style={{
                    background: activeCategories.includes(cat) ? "var(--text)" : "var(--border)",
                    color: activeCategories.includes(cat) ? "var(--bg)" : "var(--dim)",
                  }}
                  onClick={() => toggleCategory(cat)}
                  type="button"
                >
                  {cat}
                </button>
              ))}
            </div>
          )}

          <div className="mt-5 space-y-4">
            {activeCategories.map((cat) => {
              const group = allAlerts[cat];
              if (group.items.length === 0) return null;
              return (
                <div key={cat} className="rounded-[1.5rem] p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                  <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{group.label}</p>
                  <ul className="mt-3 space-y-2">
                    {group.items.map((alert) => (
                      <li key={alert.text}>
                        <Link
                          href={alert.href}
                          className="flex items-center justify-between gap-4 rounded-[1rem] px-4 py-3 text-sm transition-opacity hover:opacity-80"
                          style={{ background: "color-mix(in srgb, var(--primary) 7%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 15%, transparent)" }}
                        >
                          <span style={{ color: "var(--text)" }}>{alert.text}</span>
                          <span style={{ color: "var(--primary)" }}>→</span>
                        </Link>
                      </li>
                    ))}
                  </ul>
                </div>
              );
            })}
          </div>
        </section>

        {/* Nav Hub */}
        <section className="grid gap-6 lg:grid-cols-3">
          {NAV_GROUPS.map((group) => (
            <div key={group.label} className="rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
              <p className="text-xs font-semibold uppercase tracking-[0.26em]" style={{ color: "var(--primary)" }}>{group.label}</p>
              <div className="mt-4 space-y-2">
                {group.items.map((item) => (
                  <Link
                    key={item.href}
                    href={item.href}
                    className="flex items-center justify-between rounded-[1.3rem] px-4 py-3 text-sm font-semibold transition-opacity hover:opacity-80"
                    style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                  >
                    <span>{item.label}</span>
                    <span style={{ color: "var(--dim)" }}>→</span>
                  </Link>
                ))}
              </div>
            </div>
          ))}
        </section>

      </div>
    </main>
  );
}
