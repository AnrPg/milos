"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useRouter, useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";

import type { EffectiveEntitlement } from "@/api/my-finance";
import { fetchMyBilling, MY_BILLING_QUERY_KEY, type BillingProvider, type BillingSubscription } from "@/api/my-billing";
import { CorporateEnrollmentCard } from "@/components/client/CorporateEnrollmentCard";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { AccessNotice, EntitlementCard, formatDate, StatusBadge } from "@/components/finance/MembershipEntitlement";
import { HubCard, HubPage } from "@/components/member-app/HubParts";
import { BackToMe } from "@/components/member-app/me/BackToMe";
import { SemanticLabel } from "@/components/semantic-label";
import { useSession } from "@/components/session-provider";
import { Select } from "@/components/ui/Select";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useHasBillingProviders } from "@/lib/billing-providers";
import { formatMinorUnits } from "@/lib/finance-accounting";
import { useOrganizationSlug } from "@/lib/organization-slug";
import { inboxHref } from "@/components/chat/inbox/inbox-model";

import { billingTab, sessionsLeft, validityProgress, type BillingTab } from "./billing-model";
import { OffersSegment } from "./OffersSegment";
import { Detail, Empty, Row } from "./parts";
import { TransactionsSegment } from "./TransactionsSegment";

/**
 * Εγώ › Πληρωμές (vision §6.3, §7.11): per gym or coach the person is a
 * client of. A summary on top (package, what is left, balance, one way to
 * reach the box), then three segments in `?tab=`: «Συνδρομή» (package,
 * allowances, history, corporate plan), «Συναλλαγές» (the complete money
 * history, events at any host included) and «Προσφορές» (codes to use,
 * offers claimed, seasons, referral rewards, trials). Members cannot buy or cancel here (staff assign
 * packages), so those needs go to «Επικοινωνία με το box». Several providers
 * get a dropdown (`?box=`). People without a provider never see the entry,
 * and the route sends them back to Εγώ.
 */
export function BillingPage() {
  const t = useTranslations("Billing");
  const router = useRouter();
  const searchParams = useSearchParams();
  const { status, tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const { hasBillingProviders, isLoading } = useHasBillingProviders();
  const selectedOrganizationSlug = useOrganizationSlug();

  useEffect(() => {
    if (status === "guest") {
      // A company enrollment link (ADR-098) carries its code in the query.
      router.replace(`/login?next=${encodeURIComponent(window.location.pathname + window.location.search)}`);
    } else if (status === "authenticated" && !isLoading && !hasBillingProviders) {
      router.replace("/me");
    }
  }, [hasBillingProviders, isLoading, router, status]);

  const billing = useQuery({
    queryKey: MY_BILLING_QUERY_KEY,
    enabled: Boolean(token) && hasBillingProviders,
    queryFn: () => fetchMyBilling(token!),
    staleTime: 60_000,
  });

  const providers = billing.data?.providers ?? [];
  const requested = searchParams.get("box");
  const current =
    providers.find((provider) => provider.slug === requested) ??
    providers.find((provider) => provider.slug === selectedOrganizationSlug) ??
    providers[0] ??
    null;
  const tab = billingTab(searchParams.get("tab"));

  function setParam(key: "box" | "tab", value: string) {
    const params = new URLSearchParams(searchParams.toString());
    params.set(key, value);
    // A segment is a step Back returns from; switching provider is not.
    if (key === "tab") router.push(`?${params.toString()}`, { scroll: false });
    else router.replace(`?${params.toString()}`, { scroll: false });
  }

  if (status !== "authenticated" || isLoading || !hasBillingProviders) {
    return (
      <HubPage back={<BackToMe />} title={t("title")}>
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      </HubPage>
    );
  }

  return (
    <HubPage back={<BackToMe />} title={t("title")}>
      {providers.length > 1 && current ? (
        <Select
          aria-label={t("pickProvider")}
          value={current.slug}
          onValueChange={(value) => setParam("box", value)}
          className="min-h-11 w-full rounded-2xl px-3 text-sm font-semibold"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {providers.map((provider) => (
            <option key={provider.slug} value={provider.slug}>
              {provider.name}
            </option>
          ))}
        </Select>
      ) : null}

      {billing.isPending ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : billing.isError ? (
        <HubCard>
          <p className="text-sm" role="alert" style={{ color: "var(--text-soft)" }}>{t("loadFailed")}</p>
        </HubCard>
      ) : current ? (
        <ProviderBilling
          key={current.organization_id}
          provider={current}
          tab={tab}
          onTab={(next) => setParam("tab", next)}
          onEnrolled={() => void billing.refetch()}
        />
      ) : (
        <HubCard>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("noProvider")}</p>
        </HubCard>
      )}
    </HubPage>
  );
}

// ─── one provider ────────────────────────────────────────────────────────────

function ProviderBilling({
  provider,
  tab,
  onTab,
  onEnrolled,
}: {
  provider: BillingProvider;
  tab: BillingTab;
  onTab: (tab: BillingTab) => void;
  onEnrolled: () => void;
}) {
  const t = useTranslations("Billing");
  const entitlement = provider.entitlement
    ? ({ usage_entries: [], ...provider.entitlement } as unknown as EffectiveEntitlement)
    : null;
  const panelId = "billing-panel";

  return (
    <section aria-label={provider.name} className="flex min-w-0 flex-col gap-4">
      <div className="min-w-0">
        <p className="truncate text-lg font-extrabold" style={{ color: "var(--text)" }}>{provider.name}</p>
        <p className="text-xs" style={{ color: "var(--dim)" }}>{provider.kind === "coach" ? t("kindCoach") : t("kindGym")}</p>
      </div>

      <Summary provider={provider} entitlement={entitlement} />

      <SegmentPicker
        ariaLabel={t("sections")}
        idPrefix="billing"
        panelId={panelId}
        stretch
        value={tab}
        onChange={onTab}
        options={[
          { value: "membership", label: t("tabMembership") },
          { value: "transactions", label: t("tabTransactions") },
          { value: "offers", label: t("tabOffers") },
        ]}
      />

      <div id={panelId} role="tabpanel" aria-labelledby={`billing-tab-${tab}`} className="flex min-w-0 flex-col gap-4">
        {tab === "membership" ? (
          <MembershipSegment provider={provider} entitlement={entitlement} onEnrolled={onEnrolled} />
        ) : tab === "transactions" ? (
          <TransactionsSegment organizationId={provider.organization_id} />
        ) : (
          <OffersSegment provider={provider} currency={currencyOf(provider)} />
        )}
      </div>
    </section>
  );
}

function Summary({ provider, entitlement }: { provider: BillingProvider; entitlement: EffectiveEntitlement | null }) {
  const t = useTranslations("Billing");
  const locale = useUiLocale();
  const [now] = useState(() => new Date());
  const subscription = provider.subscriptions.find((entry) => entry.current) ?? null;
  const left = sessionsLeft(entitlement);
  const progress = subscription ? validityProgress(subscription.starts_on, subscription.ends_on, now) : null;
  const currency = currencyOf(provider);
  const due = provider.outstanding_cents > 0;

  return (
    <HubCard>
      {subscription ? (
        <div className="flex min-w-0 flex-col gap-1">
          <p className="break-words text-base font-bold" style={{ color: "var(--text)" }}>{subscription.package_name ?? t("package")}</p>
          {left ? (
            <p className="text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
              {left.unlimited ? t("unlimited") : t("sessionsLeft", { remaining: left.remaining, total: left.limit })}
            </p>
          ) : null}
          {subscription.ends_on ? (
            <>
              {progress !== null ? (
                <div
                  role="progressbar"
                  aria-label={t("validity")}
                  aria-valuemin={0}
                  aria-valuemax={100}
                  aria-valuenow={Math.round(progress * 100)}
                  className="mt-1 h-1.5 w-full overflow-hidden rounded-full"
                  style={{ background: "var(--panel-muted)" }}
                >
                  <div className="h-full rounded-full" style={{ width: `${progress * 100}%`, background: "var(--primary)" }} />
                </div>
              ) : null}
              <p className="text-xs" style={{ color: "var(--dim)" }}>
                {subscription.auto_renew === true
                  ? t("renewsOn", { date: formatDate(locale, subscription.ends_on) })
                  : t("validUntil", { date: formatDate(locale, subscription.ends_on) })}
              </p>
            </>
          ) : null}
        </div>
      ) : (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("noPackage")}</p>
      )}

      <div className="mt-4 flex min-w-0 flex-wrap items-end justify-between gap-x-4 gap-y-2">
        <div className="min-w-0">
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t("outstanding")}</p>
          <p className="text-xl font-extrabold tabular-nums" style={{ color: due ? "var(--warning)" : "var(--text)" }}>
            {formatMinorUnits(locale, provider.outstanding_cents, currency)}
          </p>
          {due ? <p className="text-xs" style={{ color: "var(--text-soft)" }}>{t("payAtBox")}</p> : null}
        </div>
        {provider.credit_balance_cents > 0 ? (
          <div className="min-w-0 text-end">
            <p className="text-xs" style={{ color: "var(--dim)" }}>{t("credit")}</p>
            <p className="text-base font-bold tabular-nums" style={{ color: "var(--success)" }}>
              {formatMinorUnits(locale, provider.credit_balance_cents, currency)}
            </p>
          </div>
        ) : null}
      </div>

      {provider.partial ? (
        <p className="mt-3 text-xs" role="status" style={{ color: "var(--warning)" }}>{t("partial")}</p>
      ) : null}

      <Link
        href={contactHref(provider)}
        className="mt-4 flex min-h-11 items-center justify-center rounded-2xl px-4 text-center text-sm font-bold"
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
      >
        {provider.kind === "coach" ? t("contactCoach") : t("contactBox")}
      </Link>
    </HubCard>
  );
}

// ─── «Συνδρομή» ──────────────────────────────────────────────────────────────

function MembershipSegment({
  provider,
  entitlement,
  onEnrolled,
}: {
  provider: BillingProvider;
  entitlement: EffectiveEntitlement | null;
  onEnrolled: () => void;
}) {
  const t = useTranslations("Billing");
  const locale = useUiLocale();
  const current = provider.subscriptions.find((entry) => entry.current) ?? null;
  const past = provider.subscriptions.filter((entry) => !entry.current);

  return (
    <>
      {current ? (
        <HubCard>
          <SubscriptionDetails subscription={current} />
          {provider.actions.self_service_purchase ? null : (
            <p className="mt-3 text-xs" style={{ color: "var(--dim)" }}>{t("renewWithBox")}</p>
          )}
        </HubCard>
      ) : (
        <Empty>{t("noPackageDetails")}</Empty>
      )}
      <AccessNotice entitlement={entitlement} />
      <EntitlementCard entitlement={entitlement} />
      {past.length > 0 ? (
        <HubCard eyebrow={t("historyTitle")}>
          <ul className="flex flex-col">
            {past.map((subscription) => (
              <Row
                key={subscription.id}
                title={subscription.package_name ?? t("package")}
                detail={`${formatDate(locale, subscription.starts_on)} – ${formatDate(locale, subscription.ends_on)}`}
                end={<StatusBadge status={subscription.status} />}
              />
            ))}
          </ul>
        </HubCard>
      ) : null}
      <CorporateEnrollmentCard onEnrolled={onEnrolled} />
    </>
  );
}

function SubscriptionDetails({ subscription }: { subscription: BillingSubscription }) {
  const t = useTranslations("Billing");
  const locale = useUiLocale();
  return (
    <dl className="flex min-w-0 flex-col gap-2 text-sm">
      <Detail label={t("status")} value={<StatusBadge status={subscription.status} />} />
      <Detail label={t("period")} value={`${formatDate(locale, subscription.starts_on)} – ${subscription.ends_on ? formatDate(locale, subscription.ends_on) : t("openEnded")}`} />
      {subscription.billing_period ? <Detail label={t("billing")} value={<SemanticLabel value={subscription.billing_period} />} /> : null}
      {typeof subscription.price_cents === "number" ? <Detail label={t("price")} value={formatMinorUnits(locale, subscription.price_cents)} /> : null}
      {subscription.auto_renew !== null && subscription.auto_renew !== undefined ? (
        <Detail label={t("autoRenew")} value={subscription.auto_renew ? t("yes") : t("no")} />
      ) : null}
      {subscription.commitment_ends_on ? <Detail label={t("commitment")} value={formatDate(locale, subscription.commitment_ends_on)} /> : null}
    </dl>
  );
}

// ─── small parts ─────────────────────────────────────────────────────────────

function contactHref(provider: BillingProvider) {
  return provider.contact.box_chat_slug ? `/b/${encodeURIComponent(provider.contact.box_chat_slug)}/chat` : inboxHref({ filter: provider.kind === "coach" ? "coach" : "clubs" });
}

function currencyOf(provider: BillingProvider) {
  return provider.invoices[0]?.currency ?? provider.payments[0]?.currency ?? "EUR";
}
