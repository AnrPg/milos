


import {useUiTranslations} from "@/i18n/ui";
import Link from "next/link";

import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default function AdminMarketingPage() {
  const MARKETING_LINKS = [
    [i18n("promotions086e09b"), "/admin/finance?tab=promotions", i18n("createAndManagePromotionalOffers46d33bb")],
    [i18n("referrals2b0e3a3"), "/admin/finance?tab=referrals", i18n("reviewReferralActivityAndRewardActions8ea1271")],
    [i18n("packages0a99901"), "/admin/finance?tab=packages", i18n("manageThePackagesUsedByMembershipsAndEntitlementsb466c1f")],
  ] as const;

  const i18n = useUiTranslations();
  return (
    <AuthGuard roles={["admin"]}>
      <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
        <div className="mx-auto max-w-5xl space-y-8">
          <section
            className="rounded-[2.4rem] p-8"
            style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
          >
            <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>
              {i18n("analyticsMarketinga05588a")}
            </p>
            <h1 className="mt-4 text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "var(--text)" }}>
              {i18n("marketingOperationsd71c522")}
            </h1>
            <p className="mt-4 max-w-3xl text-base leading-7" style={{ color: "var(--muted)" }}>
              {i18n("marketingStrategyIsGroupedHereManagementActionsOpend3d4d52")}
            </p>
          </section>

          <section className="grid gap-4 md:grid-cols-3">
            {MARKETING_LINKS.map(([label, href, description]) => (
              <Link
                key={label}
                className="rounded-[2rem] p-6 transition-transform hover:-translate-y-0.5"
                href={href}
                style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
              >
                <p className="text-lg font-semibold" style={{ color: "var(--text)" }}>{label}</p>
                <p className="mt-3 text-sm leading-6" style={{ color: "var(--muted)" }}>{description}</p>
                <p className="mt-5 text-sm font-semibold" style={{ color: "var(--primary)" }}>{i18n("openInFinanceabe0a86")}</p>
              </Link>
            ))}
          </section>
        </div>
      </main>
    </AuthGuard>
  );
}
