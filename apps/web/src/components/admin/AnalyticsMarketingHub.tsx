"use client";





import {useUiTranslations} from "@/i18n/ui";
import Link from "next/link";

import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { PageHeader } from "@/components/PageHeader";

export function AnalyticsMarketingHub() {
  const i18n = useUiTranslations();
  const organizationSlug = useOrganizationSlug();
  const SECTIONS = [
    {
      title: i18n("overview0efc2e6"),
      description: i18n("crossDomainSignalsAndACompactViewOf0bf1ada"),
      href: "/admin/metrics/overview",
    },
    {
      title: i18n("financeAnalytics107dfa1"),
      description: i18n("membershipRevenuePackageRenewalAndRetentionReporting45d89f2"),
      href: "/admin/metrics/finance",
    },
    {
      title: i18n("trainingAnalytics2c25dde"),
      description: i18n("attendanceCompletionsWorkoutTypesAndPerformanceTrends77b2f11"),
      href: "/admin/metrics/training",
    },
    {
      title: i18n("coachingAnalyticsb6ddda1"),
      description: i18n("athleteActivityAdherenceAssignmentCompletionAndFollowUp144ce93"),
      href: "/admin/metrics/coaching",
    },
    {
      title: i18n("userEngagement72f61cf"),
      description: i18n("reviewsCommunicationNotificationsAndInteractionSignals6592ffe"),
      href: "/admin/metrics/engagement",
    },
    {
      title: i18n("healthIncidentsb8da1fe"),
      description: i18n("aggregateInjuryLimitationSeverityAndUnresolvedReportSignals1fecbcf"),
      href: "/admin/metrics/health",
    },
    {
      title: i18n("challengesff38765"),
      description: i18n("manageSeasonalEngagementCampaignsAndReviewParticipationdf0bc50"),
      href: "/admin/challenges",
    },
    {
      title: i18n("marketinge0c534a"),
      description: i18n("openPromotionsReferralsAndPackagesInTheirFinance7288c8e"),
      href: "/admin/metrics/marketing",
    },
  ] as const;
  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-6xl space-y-8">
        <PageHeader title={i18n("analyticsMarketinga05588a")} />

        <section className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          {SECTIONS.map((section) => (
            <Link
              key={section.title}
              href={adminHref(section.href, organizationSlug)}
              className="group flex min-h-52 flex-col rounded-[2rem] p-6 transition-transform hover:-translate-y-0.5"
              style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
            >
              <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--primary)" }}>
                {section.title}
              </p>
              <p className="mt-4 flex-1 text-sm leading-6" style={{ color: "var(--muted)" }}>
                {section.description}
              </p>
              <p className="mt-5 text-sm font-semibold" style={{ color: "var(--text)" }}>
                {i18n("opencf9b770")} <span className="inline-block transition-transform group-hover:translate-x-1 rtl:rotate-180 rtl:group-hover:-translate-x-1">→</span>
              </p>
            </Link>
          ))}
        </section>
      </div>
    </main>
  );
}
