"use client";

import Link from "next/link";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";

import { fetchAdminAnalyticsSummary } from "@/api/analytics";
import { fetchFinanceSummary } from "@/api/finance";
import { useSession } from "@/components/session-provider";

export function AdminHome() {
  const { currentUser, signOut, tokens } = useSession();
  const [activeTab, setActiveTab] = useState<"finance" | "coaching">("finance");

  const financeQuery = useQuery({
    queryKey: ["admin", "dashboard", "finance"],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => fetchFinanceSummary(tokens!.access_token),
  });

  const analyticsQuery = useQuery({
    queryKey: ["admin", "dashboard", "analytics"],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => fetchAdminAnalyticsSummary(tokens!.access_token),
  });

  const financeTotals = (financeQuery.data?.totals ?? {}) as Record<string, unknown>;
  const dashboard = (analyticsQuery.data?.dashboard ?? {}) as Record<string, Record<string, unknown>>;
  const coachingDashboard = dashboard.coaching ?? {};

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-5xl space-y-8">
        <section className="rounded-[2.4rem] p-8" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <div className="flex flex-wrap items-start justify-between gap-4">
            <div>
              <p className="text-sm font-semibold uppercase tracking-[0.28em] text-[var(--primary)]">Admin dashboard</p>
              <h1 className="mt-4 text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "var(--text)" }}>
                Finance and coaching
              </h1>
              <p className="mt-4 text-base leading-7" style={{ color: "var(--muted)" }}>
                Signed in as{" "}
                <span className="font-semibold" style={{ color: "var(--text-soft)" }}>
                  {currentUser?.nickname}
                </span>
                .
              </p>
            </div>
            <button
              className="rounded-full px-5 py-3 text-sm font-semibold"
              style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", color: "var(--primary)", border: "1px solid color-mix(in srgb, var(--primary) 24%, transparent)" }}
              onClick={signOut}
              type="button"
            >
              Log out
            </button>
          </div>
        </section>

        <section className="rounded-[2.4rem] p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <div className="grid gap-2 rounded-[1.8rem] p-2 md:grid-cols-2" style={{ background: "var(--panel-muted)" }}>
            {[
              ["finance", "Finance"],
              ["coaching", "Coaching"],
            ].map(([key, label]) => (
              <button
                key={key}
                className="rounded-[1.3rem] px-4 py-3 text-sm font-bold"
                style={{
                  background: activeTab === key ? "var(--text)" : "transparent",
                  color: activeTab === key ? "var(--bg)" : "var(--text-soft)",
                }}
                onClick={() => setActiveTab(key as "finance" | "coaching")}
                type="button"
              >
                {label}
              </button>
            ))}
          </div>

          {activeTab === "finance" ? (
            <DashboardTab
              cards={[
                ["Active memberships", financeTotals.active_memberships],
                ["Expiring soon", financeTotals.expiring_memberships],
                ["Paid revenue", cents(financeTotals.paid_revenue_cents)],
              ]}
              links={[
                ["Finance console", "/admin/finance"],
                ["Metrics", "/admin/metrics"],
                ["Search", "/admin/finance"],
              ]}
              pending={financeQuery.isLoading}
            />
          ) : (
            <DashboardTab
              cards={[
                ["Events captured", coachingDashboard.event_count],
                ["Reviews", coachingDashboard.review_count],
                ["Injuries", coachingDashboard.injury_count],
              ]}
              links={[
                ["Coaching notes", "/admin/coaching"],
                ["Reviews", "/admin/reviews"],
                ["Wellbeing", "/admin/wellbeing"],
              ]}
              pending={analyticsQuery.isLoading}
            />
          )}
        </section>

        <section className="grid gap-4 md:grid-cols-4">
          {[
            { label: "Workout list", route: "/admin/workouts", href: "/admin/workouts" },
            { label: "Workout creation", route: "/admin/workouts/new", href: "/admin/workouts/new" },
            { label: "Schedule", route: "/admin/schedule", href: "/admin/schedule" },
            { label: "Challenges", route: "/admin/challenges", href: "/admin/challenges" },
            { label: "Settings", route: "/admin/settings", href: "/admin/settings" },
            { label: "Coaching", route: "/admin/coaching", href: "/admin/coaching" },
            { label: "Metrics", route: "/admin/metrics", href: "/admin/metrics" },
            { label: "Finance", route: "/admin/finance", href: "/admin/finance" },
            { label: "Reviews", route: "/admin/reviews", href: "/admin/reviews" },
            { label: "Wellbeing", route: "/admin/wellbeing", href: "/admin/wellbeing" },
            { label: "Athlete week view", route: "/my-workouts", href: "/my-workouts" },
          ].map(({ label, route, href }) => (
            <Link
              key={href}
              className="rounded-[1.8rem] p-6 transition-colors"
              style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
              href={href}
            >
              <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>{label}</p>
              <p className="mt-3 text-xl font-semibold" style={{ color: "var(--text)" }}>{route}</p>
            </Link>
          ))}
        </section>
      </div>
    </main>
  );
}

function DashboardTab({
  cards,
  links,
  pending,
}: {
  cards: Array<[string, unknown]>;
  links: Array<[string, string]>;
  pending: boolean;
}) {
  return (
    <div className="grid gap-4 p-4 lg:grid-cols-[1fr_0.55fr]">
      <div className="grid gap-4 md:grid-cols-3">
        {cards.map(([label, value]) => (
          <div key={label} className="rounded-[1.4rem] p-5" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
            <p className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
              {label}
            </p>
            <p className="mt-3 text-2xl font-semibold" style={{ color: "var(--text)" }}>
              {pending ? "..." : displayValue(value)}
            </p>
          </div>
        ))}
      </div>
      <div className="grid gap-3">
        {links.map(([label, href]) => (
          <Link
            key={href + label}
            className="rounded-[1.4rem] px-5 py-4 text-sm font-semibold"
            href={href}
            style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", color: "var(--primary-strong)", border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)" }}
          >
            {label}
          </Link>
        ))}
      </div>
    </div>
  );
}

function displayValue(value: unknown) {
  if (value === null || value === undefined || value === "") return "0";
  return String(value);
}

function cents(value: unknown) {
  const amount = typeof value === "number" ? value : Number(value ?? 0);
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "EUR" }).format(amount / 100);
}
