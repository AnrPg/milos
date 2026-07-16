"use client";






import {useUiLocale} from "@/i18n/use-ui-locale";
import {useUiTranslations} from "@/i18n/ui";
import Link from "next/link";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";

import { fetchAdminAnalyticsSummary } from "@/api/analytics";
import { fetchFinanceSummary } from "@/api/finance";
import { useSession } from "@/components/session-provider";

export function AdminHome() {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
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
              <p className="text-sm font-semibold uppercase tracking-[0.28em] text-[var(--primary)]">{i18n("adminDashboard25031b2")}</p>
              <h1 className="mt-4 text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "var(--text)" }}>
                {i18n("financeAndCoaching8e4276c")}
              </h1>
              <p className="mt-4 text-base leading-7" style={{ color: "var(--muted)" }}>
                {i18n("signedInAsa02107c")}{" "}
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
              {i18n("logOut6e78c91")}
            </button>
          </div>
        </section>

        <section className="rounded-[2.4rem] p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <div className="grid gap-2 rounded-[1.8rem] p-2 md:grid-cols-2" style={{ background: "var(--panel-muted)" }}>
            {[
              ["finance", i18n("finance1b48d3f")],
              ["coaching", i18n("coachingfd8b79f")],
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
                [i18n("activeMemberships0d117fb"), financeTotals.active_memberships],
                [i18n("expiringSoon74bbe75"), financeTotals.expiring_memberships],
                [i18n("paidRevenue64c34e5"), cents(uiLocale, financeTotals.paid_revenue_cents)],
              ]}
              links={[
                [i18n("financeConsole35f368f"), "/admin/finance"],
                [i18n("metricsddf6a1f"), "/admin/metrics"],
                [i18n("searchbce0641"), "/admin/finance"],
              ]}
              pending={financeQuery.isLoading}
            />
          ) : (
            <DashboardTab
              cards={[
                [i18n("eventsCaptured5288ab8"), coachingDashboard.event_count],
                [i18n("reviewsb83c4cd"), coachingDashboard.review_count],
                [i18n("injuries698c06d"), coachingDashboard.injury_count],
              ]}
              links={[
                [i18n("coachingNotes5c7da9f"), "/admin/coaching"],
                [i18n("reviewsb83c4cd"), "/admin/reviews"],
                [i18n("wellbeinga85b236"), "/admin/wellbeing"],
              ]}
              pending={analyticsQuery.isLoading}
            />
          )}
        </section>

        <section className="grid gap-4 md:grid-cols-4">
          {[
            { label: i18n("workoutList1f538d5"), route: "/admin/workouts", href: "/admin/workouts" },
            { label: i18n("workoutCreation3d2fe38"), route: "/admin/workouts/new", href: "/admin/workouts/new" },
            { label: i18n("schedule0a8adac"), route: "/admin/schedule", href: "/admin/schedule" },
            { label: i18n("challengesff38765"), route: "/admin/challenges", href: "/admin/challenges" },
            { label: i18n("settingsc7f73bb"), route: "/admin/settings", href: "/admin/settings" },
            { label: i18n("coachingfd8b79f"), route: "/admin/coaching", href: "/admin/coaching" },
            { label: i18n("metricsddf6a1f"), route: "/admin/metrics", href: "/admin/metrics" },
            { label: i18n("finance1b48d3f"), route: "/admin/finance", href: "/admin/finance" },
            { label: i18n("reviewsb83c4cd"), route: "/admin/reviews", href: "/admin/reviews" },
            { label: i18n("wellbeinga85b236"), route: "/admin/wellbeing", href: "/admin/wellbeing" },
            { label: i18n("athleteWeekViewfc0f571"), route: "/my-workouts", href: "/my-workouts" },
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

function cents(uiLocale: string, value: unknown) {
  const amount = typeof value === "number" ? value : Number(value ?? 0);
  return new Intl.NumberFormat(uiLocale, { style: "currency", currency: "EUR" }).format(amount / 100);
}
