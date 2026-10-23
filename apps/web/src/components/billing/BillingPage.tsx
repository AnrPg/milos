"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useRouter, useSearchParams } from "next/navigation";
import { useEffect, useState, type ReactNode } from "react";

import type { EffectiveEntitlement } from "@/api/my-finance";
import {
  fetchMyBilling,
  fetchProviderRefundReceiptDocument,
  getProviderInvoiceDownloadUrl,
  MY_BILLING_QUERY_KEY,
  type BillingProvider,
  type BillingSubscription,
} from "@/api/my-billing";
import { CorporateEnrollmentCard } from "@/components/client/CorporateEnrollmentCard";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { AccessNotice, EntitlementCard, formatDate, StatusBadge } from "@/components/finance/MembershipEntitlement";
import { RefundReceiptDocumentDialog } from "@/components/finance/RefundReceiptDocumentDialog";
import { HubCard, HubPage } from "@/components/member-app/HubParts";
import { SemanticLabel } from "@/components/semantic-label";
import { useSession } from "@/components/session-provider";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { Select } from "@/components/ui/Select";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useHasBillingProviders } from "@/lib/billing-providers";
import { formatMinorUnits } from "@/lib/finance-accounting";
import { useOrganizationSlug } from "@/lib/organization-slug";

import {
  billingDocuments,
  billingTab,
  DOCUMENT_FILTER_THRESHOLD,
  filterDocuments,
  sessionsLeft,
  validityProgress,
  type BillingDocument,
  type BillingTab,
  type DocumentFilter,
} from "./billing-model";

type T = ReturnType<typeof useTranslations<"Billing">>;

/**
 * Εγώ › Πληρωμές (vision §6.3, §7.11): per gym or coach the person is a
 * client of. A summary on top (package, what is left, balance, one way to
 * reach the box), then three segments in `?tab=`: «Συνδρομή» (package,
 * allowances, history, corporate plan), «Αποδείξεις» (invoices, payments and
 * refund receipts in one list) and «Προσφορές» (offers, seasons, referral
 * rewards, trials). Members cannot buy or cancel here (staff assign
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
    router.replace(`?${params.toString()}`, { scroll: false });
  }

  if (status !== "authenticated" || isLoading || !hasBillingProviders) {
    return (
      <HubPage title={t("title")}>
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      </HubPage>
    );
  }

  return (
    <HubPage title={t("title")}>
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
          { value: "documents", label: t("tabDocuments") },
          { value: "offers", label: t("tabOffers") },
        ]}
      />

      <div id={panelId} role="tabpanel" aria-labelledby={`billing-tab-${tab}`} className="flex min-w-0 flex-col gap-4">
        {tab === "membership" ? (
          <MembershipSegment provider={provider} entitlement={entitlement} onEnrolled={onEnrolled} />
        ) : tab === "documents" ? (
          <DocumentsSegment provider={provider} />
        ) : (
          <OffersSegment provider={provider} />
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

// ─── «Αποδείξεις» ────────────────────────────────────────────────────────────

function DocumentsSegment({ provider }: { provider: BillingProvider }) {
  const t = useTranslations("Billing");
  const locale = useUiLocale();
  const documents = billingDocuments(provider);
  const [filter, setFilter] = useState<DocumentFilter>("all");
  const [open, setOpen] = useState<BillingDocument | null>(null);
  const shown = filterDocuments(documents, documents.length > DOCUMENT_FILTER_THRESHOLD ? filter : "all");

  if (documents.length === 0) return <Empty>{t("noDocuments")}</Empty>;

  return (
    <>
      {documents.length > DOCUMENT_FILTER_THRESHOLD ? (
        <Select
          aria-label={t("filterDocuments")}
          value={filter}
          onValueChange={(value) => setFilter(value as DocumentFilter)}
          className="min-h-11 w-full rounded-2xl px-3 text-sm font-semibold"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
        >
          <option value="all">{t("filterAll")}</option>
          <option value="invoice">{t("filterInvoices")}</option>
          <option value="payment">{t("filterPayments")}</option>
          <option value="refund">{t("filterRefunds")}</option>
        </Select>
      ) : null}
      <HubCard>
        <ul className="flex flex-col">
          {shown.map((document) => (
            <li key={document.key} style={{ borderBottom: "1px solid var(--border)" }}>
              <button
                type="button"
                onClick={() => setOpen(document)}
                className="flex min-h-12 w-full min-w-0 items-center gap-3 py-2.5 text-start"
              >
                <KindIcon kind={document.kind} />
                <span className="flex min-w-0 flex-1 flex-col">
                  <span className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{documentTitle(t, document)}</span>
                  <span className="truncate text-xs" style={{ color: "var(--dim)" }}>{document.date ? formatDate(locale, document.date) : "—"}</span>
                </span>
                <span className="flex shrink-0 flex-col items-end gap-1">
                  <span className="text-sm font-bold tabular-nums" style={{ color: "var(--text)" }}>
                    {formatMinorUnits(locale, document.amountCents, document.currency)}
                  </span>
                  {document.status ? <StatusBadge status={document.status} /> : null}
                </span>
              </button>
            </li>
          ))}
        </ul>
      </HubCard>
      {open ? <DocumentDialog document={open} slug={provider.slug} onClose={() => setOpen(null)} /> : null}
    </>
  );
}

function DocumentDialog({ document, slug, onClose }: { document: BillingDocument; slug: string; onClose: () => void }) {
  const t = useTranslations("Billing");
  const locale = useUiLocale();
  const { tokens } = useSession();
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);
  const [receipt, setReceipt] = useState<string | null>(null);

  async function download() {
    if (!tokens?.access_token) return;
    setBusy(true);
    setFailed(false);
    try {
      if (document.kind === "refund") {
        setReceipt(await fetchProviderRefundReceiptDocument(tokens.access_token, slug, document.id, locale));
      } else {
        const data = await getProviderInvoiceDownloadUrl(tokens.access_token, slug, document.id);
        if (data?.download_url) window.open(data.download_url, "_blank", "noopener,noreferrer");
      }
    } catch {
      setFailed(true);
    } finally {
      setBusy(false);
    }
  }

  if (receipt) {
    return <RefundReceiptDocumentDialog html={receipt} receiptNumber={document.number ?? ""} onClose={onClose} />;
  }

  return (
    <Dialog
      onClose={onClose}
      title={documentTitle(t, document)}
      closeLabel={t("close")}
      variant="sheet"
      size="sm"
      footer={
        <>
          <DialogButton onClick={onClose}>{t("close")}</DialogButton>
          {document.downloadable ? (
            <DialogButton tone="primary" onClick={() => void download()} disabled={busy}>
              {document.kind === "refund" ? t("view") : t("download")}
            </DialogButton>
          ) : null}
        </>
      }
    >
      <dl className="flex flex-col gap-2 text-sm">
        <Detail label={t("amount")} value={formatMinorUnits(locale, document.amountCents, document.currency)} />
        <Detail label={t("date")} value={document.date ? formatDate(locale, document.date) : "—"} />
        {document.status ? <Detail label={t("status")} value={<StatusBadge status={document.status} />} /> : null}
        {document.kind === "invoice" && document.dueDate ? <Detail label={t("dueDate")} value={formatDate(locale, document.dueDate)} /> : null}
        {document.kind === "invoice" && (document.balanceDueCents ?? 0) > 0 ? (
          <Detail label={t("outstanding")} value={formatMinorUnits(locale, document.balanceDueCents ?? 0, document.currency)} />
        ) : null}
        {document.method ? <Detail label={t("method")} value={<SemanticLabel value={document.method} />} /> : null}
        {document.invoiceNumber ? <Detail label={t("invoice")} value={document.invoiceNumber} /> : null}
        {document.reason ? <Detail label={t("reason")} value={document.reason} /> : null}
      </dl>
      {!document.downloadable ? <p className="mt-3 text-xs" style={{ color: "var(--dim)" }}>{t("noPdf")}</p> : null}
      {failed ? <p className="mt-3 text-xs" role="alert" style={{ color: "var(--danger)" }}>{t("downloadFailed")}</p> : null}
    </Dialog>
  );
}

function documentTitle(t: T, document: BillingDocument) {
  const label =
    document.kind === "payment"
      ? t("payment")
      : document.kind === "refund"
        ? t("refund")
        : document.documentKind === "receipt"
          ? t("receipt")
          : t("invoice");
  return document.number ? `${label} ${document.number}` : label;
}

function KindIcon({ kind }: { kind: BillingDocument["kind"] }) {
  const glyph = kind === "invoice" ? "🧾" : kind === "payment" ? "€" : "↩";
  return (
    <span
      aria-hidden="true"
      className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-sm font-bold"
      style={{ background: "var(--panel-muted)", color: kind === "refund" ? "var(--success)" : "var(--text-soft)" }}
    >
      {glyph}
    </span>
  );
}

// ─── «Προσφορές» ─────────────────────────────────────────────────────────────

function OffersSegment({ provider }: { provider: BillingProvider }) {
  const t = useTranslations("Billing");
  const locale = useUiLocale();
  const currency = currencyOf(provider);
  const referrals = provider.referrals;
  const hasReferrals = referrals.invited > 0 || referrals.credits.length > 0;
  const empty = provider.promotions.length === 0 && provider.seasons.length === 0 && provider.trials.length === 0 && !hasReferrals;
  const inviteLink = (
    <Link
      href={`/me/referrals?box=${encodeURIComponent(provider.slug)}`}
      className="inline-flex min-h-11 items-center text-sm font-semibold"
      style={{ color: "var(--primary-strong)" }}
    >
      {t("inviteFriend")} ›
    </Link>
  );

  if (empty) {
    return (
      <div className="flex flex-col">
        <Empty>{t("noOffers")}</Empty>
        {inviteLink}
      </div>
    );
  }

  return (
    <>
      {provider.promotions.length > 0 ? (
        <HubCard eyebrow={t("offersTitle")}>
          <ul className="flex flex-col">
            {provider.promotions.map((promotion) => (
              <Row
                key={promotion.id}
                title={promotion.campaign_name ?? t("offer")}
                detail={promotion.redeemed_at ? formatDate(locale, promotion.redeemed_at) : null}
                end={<span className="text-sm font-semibold" style={{ color: "var(--success)" }}>{discountText(t, locale, promotion, currency)}</span>}
              />
            ))}
          </ul>
        </HubCard>
      ) : null}
      {provider.seasons.length > 0 ? (
        <HubCard eyebrow={t("seasonsTitle")}>
          <ul className="flex flex-col">
            {provider.seasons.map((season) => (
              <Row
                key={season.id}
                title={season.title}
                detail={`${formatDate(locale, season.starts_on)} – ${formatDate(locale, season.ends_on)}`}
                end={<StatusBadge status={season.status} />}
              />
            ))}
          </ul>
        </HubCard>
      ) : null}
      <HubCard eyebrow={t("referralsTitle")}>
        {hasReferrals ? (
          <>
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>
              {t("referralCounts", { invited: referrals.invited, paid: referrals.paid })}
            </p>
            {referrals.credit_total_cents > 0 ? (
              <p className="mt-1 text-sm font-bold tabular-nums" style={{ color: "var(--success)" }}>
                {t("rewardsTotal", { amount: formatMinorUnits(locale, referrals.credit_total_cents, currency) })}
              </p>
            ) : null}
            {referrals.credits.length > 0 ? (
              <ul className="mt-2 flex flex-col">
                {referrals.credits.map((credit) => (
                  <Row
                    key={credit.id}
                    title={credit.description ?? t("referralReward")}
                    detail={credit.occurred_on ? formatDate(locale, credit.occurred_on) : null}
                    end={<span className="text-sm font-semibold tabular-nums">{formatMinorUnits(locale, credit.amount_cents, credit.currency)}</span>}
                  />
                ))}
              </ul>
            ) : null}
          </>
        ) : null}
        {inviteLink}
      </HubCard>
      {provider.trials.length > 0 ? (
        <HubCard eyebrow={t("trialsTitle")}>
          <ul className="flex flex-col">
            {provider.trials.map((trial) => (
              <Row
                key={trial.id}
                title={trial.class_name ?? t("trial")}
                detail={trial.class_starts_at ? formatDate(locale, trial.class_starts_at) : null}
                end={<StatusBadge status={trial.status} />}
              />
            ))}
          </ul>
        </HubCard>
      ) : null}
    </>
  );
}

// ─── small parts ─────────────────────────────────────────────────────────────

function contactHref(provider: BillingProvider) {
  return provider.contact.box_chat_slug ? `/b/${encodeURIComponent(provider.contact.box_chat_slug)}/chat` : "/me/activity/chats";
}

function Row({ title, detail, end }: { title: ReactNode; detail?: ReactNode; end?: ReactNode }) {
  return (
    <li className="flex min-w-0 items-center justify-between gap-3 py-2.5" style={{ borderBottom: "1px solid var(--border)" }}>
      <div className="flex min-w-0 flex-1 flex-col">
        <span className="break-words text-sm font-semibold" style={{ color: "var(--text)" }}>{title}</span>
        {detail ? <span className="break-words text-xs" style={{ color: "var(--dim)" }}>{detail}</span> : null}
      </div>
      {end ? <div className="shrink-0">{end}</div> : null}
    </li>
  );
}

function Detail({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="flex min-w-0 items-center justify-between gap-3">
      <dt style={{ color: "var(--dim)" }}>{label}</dt>
      <dd className="min-w-0 break-words text-end font-semibold" style={{ color: "var(--text)" }}>{value}</dd>
    </div>
  );
}

function Empty({ children }: { children: ReactNode }) {
  return <p className="text-sm" style={{ color: "var(--dim)" }}>{children}</p>;
}

function currencyOf(provider: BillingProvider) {
  return provider.invoices[0]?.currency ?? provider.payments[0]?.currency ?? "EUR";
}

function discountText(t: T, locale: string, promotion: BillingProvider["promotions"][number], currency: string) {
  const value = promotion.discount_value;
  switch (promotion.discount_type) {
    case "percent":
      return value == null ? t("discount") : `−${value}%`;
    case "fixed_amount":
      return value == null ? t("discount") : `−${formatMinorUnits(locale, value, currency)}`;
    case "free_period":
      return t("freePeriod");
    default:
      return t("discount");
  }
}
