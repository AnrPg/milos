"use client";






import {useUiLocale} from "@/i18n/use-ui-locale";
import {useUiTranslations} from "@/i18n/ui";
import { useEffect, useRef, useState } from "react";

import { fetchMyEntitlement, fetchMyFinance, getMyInvoiceDownloadUrl, type EffectiveEntitlement, type MyFinanceData } from "@/api/my-finance";
import { useRouter } from "next/navigation";
import { useSession } from "@/components/session-provider";
import { CorporateEnrollmentCard } from "@/components/client/CorporateEnrollmentCard";
import { USER_SYNC_EVENT, type UserSyncDetail } from "@/lib/user-sync";
import { SemanticLabel } from "@/components/semantic-label";
import { MyRefundReceipts } from "@/components/finance/MyRefundReceipts";
import { semanticLabel } from "@/i18n/presentation";
import {
  AccessNotice,
  EntitlementCard,
  formatDate,
  StatusBadge,
} from "@/components/finance/MembershipEntitlement";

// ─── helpers ──────────────────────────────────────────────────────────────────

function formatCents(uiLocale: string, cents: number | null | undefined, currency = "EUR") {
  if (cents == null) return "—";
  return new Intl.NumberFormat(uiLocale, {
    style: "currency",
    currency: (currency as string) || "EUR",
    minimumFractionDigits: 2,
  }).format(cents / 100);
}

function packageLabel(subscription: Record<string, unknown> | null | undefined) {
  return String(
    subscription?.package_name ??
      subscription?.package_code_snapshot ??
      subscription?.package_family_snapshot ??
      "—",
  );
}

function PackageSidePanel({
  packages,
  onClose,
}: {
  packages: Record<string, unknown>[];
  onClose: () => void;
}) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handleKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose();
    }
    document.addEventListener("keydown", handleKey);
    return () => document.removeEventListener("keydown", handleKey);
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 z-50 flex justify-end"
      style={{ background: "rgba(0,0,0,0.55)" }}
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div
        ref={ref}
        className="flex flex-col h-full overflow-y-auto w-full max-w-sm"
        style={{
          background: "var(--panel-muted)",
          borderInlineStart: "1px solid var(--border)",
          padding: "2rem 1.5rem",
          gap: "1.25rem",
        }}
      >
        <div className="flex items-center justify-between">
          <h2 className="text-base font-semibold" style={{ color: "var(--text)" }}>
            {i18n("availablePackages48a5129")}
          </h2>
          <button
            type="button"
            onClick={onClose}
            className="text-sm"
            style={{ color: "var(--dim)" }}
          >
            {i18n("closebf5d9ce")}
          </button>
        </div>

        {packages.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>
            {i18n("noPackagesAvailable14160fb")}
          </p>
        ) : (
          packages.map((pkg) => {
            const name = String(pkg.name ?? pkg.code ?? i18n("package7431e3d"));
            const packageType = pkg.package_type ? semanticLabel(String(pkg.package_type), i18n) : null;
            const billing = pkg.billing_period ? String(pkg.billing_period) : null;
            const price = typeof pkg.base_price_cents === "number" ? pkg.base_price_cents : null;
            const currency = String(pkg.currency ?? i18n("eurd06e073"));
            const description = pkg.description ? String(pkg.description) : null;
            const active = pkg.active === true;

            return (
              <div
                key={String(pkg.id)}
                className="rounded-xl p-4 flex flex-col gap-1.5"
                style={{
                  background: "var(--border)",
                  border: "1px solid var(--border)",
                  opacity: active ? 1 : 0.5,
                }}
              >
                <div className="flex items-start justify-between gap-2">
                  <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                    {name}
                  </span>
                  {!active && (
                    <span className="text-[10px] font-medium" style={{ color: "var(--dim)" }}>
                      {i18n("unavailable2c9c1f7")}
                    </span>
                  )}
                </div>
                {packageType && (
                  <span className="text-xs" style={{ color: "var(--dim)" }}>
                    {packageType}
                    {billing ? " · " + semanticLabel(billing, i18n) : ""}
                  </span>
                )}
                {price != null && (
                  <span className="text-sm font-medium" style={{ color: "var(--text-soft)" }}>
                    {formatCents(uiLocale, price, currency)}
                    {billing ? ` / ${billing}` : ""}
                  </span>
                )}
                {description && (
                  <p className="text-xs mt-1" style={{ color: "var(--dim)" }}>
                    {description}
                  </p>
                )}
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}

// ─── invoice row ──────────────────────────────────────────────────────────────

function BalanceDueBadge({ cents }: { cents: number }) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  if (cents <= 0) return null;
  return (
    <span
      className="inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-semibold"
      style={{
        background: "color-mix(in srgb, var(--danger) 12%, transparent)",
        color: "var(--danger)",
      }}
    >
      {formatCents(uiLocale, cents)} {i18n("due30cdf73")}
    </span>
  );
}

function InvoiceRow({
  invoice,
  token,
}: {
  invoice: Record<string, unknown>;
  token: string;
}) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const [downloading, setDownloading] = useState(false);
  const invoiceId = String(invoice.id);
  const hasFile = Boolean(
    (invoice.params as Record<string, unknown> | null)?.["file_key"],
  );
  const balanceDueCents =
    typeof invoice.balance_due_cents === "number" ? invoice.balance_due_cents : 0;

  async function handleDownload() {
    if (!hasFile) return;
    setDownloading(true);
    try {
      const data = await getMyInvoiceDownloadUrl(token, invoiceId);
      if (data?.download_url) {
        window.open(data.download_url, "_blank", "noopener,noreferrer");
      }
    } finally {
      setDownloading(false);
    }
  }

  return (
    <tr style={{ borderBottom: "1px solid var(--border)" }}>
      <td className="py-3 pe-4 text-sm font-mono" style={{ color: "var(--text-soft)" }}>
        {String(invoice.invoice_number ?? "—")}
      </td>
      <td className="py-3 pe-4 text-sm" style={{ color: "var(--text)" }}>
        {formatCents(uiLocale, 
          typeof invoice.total_cents === "number" ? invoice.total_cents : null,
          String(invoice.currency ?? i18n("eurd06e073")),
        )}
      </td>
      <td className="py-3 pe-4">
        <div className="flex items-center gap-2 flex-wrap">
          <StatusBadge status={String(invoice.status ?? "")} />
          <BalanceDueBadge cents={balanceDueCents} />
        </div>
      </td>
      <td className="py-3 pe-4 text-sm" style={{ color: "var(--dim)" }}>
        {formatDate(uiLocale, invoice.due_date as string | null)}
      </td>
      <td className="py-3 text-end">
        {hasFile ? (
          <button
            type="button"
            onClick={() => void handleDownload()}
            disabled={downloading}
            className="text-xs font-medium transition-opacity"
            style={{ color: "var(--primary-strong)", opacity: downloading ? 0.5 : 1 }}
          >
            {downloading ? "…" : i18n("downloada479c9c")}
          </button>
        ) : (
          <span className="text-xs" style={{ color: "var(--border-strong)" }}>
            —
          </span>
        )}
      </td>
    </tr>
  );
}

// ─── page ─────────────────────────────────────────────────────────────────────

export default function BillingPage() {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const { tokens, status } = useSession();
  const accessToken = tokens?.access_token ?? null;
  const router = useRouter();

  // Guests sign in first and come back here, query string included (a
  // company enrollment link carries its code in it).
  useEffect(() => {
    if (status === "guest") {
      router.replace(`/login?next=${encodeURIComponent(window.location.pathname + window.location.search)}`);
    }
  }, [router, status]);

  const [finance, setFinance] = useState<MyFinanceData | null>(null);
  const [entitlement, setEntitlement] = useState<EffectiveEntitlement | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showPackages, setShowPackages] = useState(false);

  useEffect(() => {
    if (!accessToken) return;
    let cancelled = false;

    queueMicrotask(() => {
      if (!cancelled) {
        setLoading(true);
        setError(null);
      }
    });

    Promise.all([fetchMyFinance(accessToken), fetchMyEntitlement(accessToken)])
      .then(([data, entitlementData]) => {
        if (!cancelled) {
          setFinance(data);
          setEntitlement(entitlementData.entitlement);
          setLoading(false);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setError(i18n("couldNotLoadBillingInformation2cc574e"));
          setLoading(false);
        }
      });

    return () => {
      cancelled = true;
    };
  }, [accessToken, i18n]);

  useEffect(() => {
    if (!accessToken) return;
    const token = accessToken;
    function handleUserSync(event: Event) {
      const detail = (event as CustomEvent<UserSyncDetail>).detail;
      if (detail.scopes.includes("finance_entitlement")) {
        void fetchMyEntitlement(token).then((data) => setEntitlement(data.entitlement));
      }
    }
    window.addEventListener(USER_SYNC_EVENT, handleUserSync as EventListener);
    return () => window.removeEventListener(USER_SYNC_EVENT, handleUserSync as EventListener);
  }, [accessToken]);

  // A new corporate seat changes the package and benefits; refresh in place.
  function refreshAfterEnrollment() {
    if (!accessToken) return;
    void Promise.all([fetchMyFinance(accessToken), fetchMyEntitlement(accessToken)])
      .then(([data, entitlementData]) => {
        setFinance(data);
        setEntitlement(entitlementData.entitlement);
      })
      .catch(() => {});
  }

  const membership = finance?.membership as Record<string, unknown> | null;
  const activeSub = finance?.active_package_subscription as Record<string, unknown> | null;
  const promoRedemptions = (finance?.promotion_redemptions ?? []) as Record<string, unknown>[];
  const latestPromo = promoRedemptions[0] ?? null;

  const referralCredits = (finance?.referral_credits ?? []) as Record<string, unknown>[];
  const totalReferralCents = referralCredits.reduce((sum, e) => {
    const v = typeof e.amount_cents === "number" ? e.amount_cents : 0;
    return sum + (v > 0 ? v : 0);
  }, 0);
  const hasCredits = (finance?.credit_balance ?? 0) > 0 || totalReferralCents > 0;

  return (
    <div className="min-h-screen" style={{ background: "var(--bg)" }}>
      <div className="max-w-3xl mx-auto px-4 py-10 flex flex-col gap-8">

        {/* header */}
        <div className="flex items-center justify-between">
          <h1 className="text-2xl font-semibold tracking-tight md:text-3xl" style={{ color: "var(--text)" }}>{i18n("billingabaec45")}</h1>
          <button
            type="button"
            onClick={() => setShowPackages(true)}
            className="text-xs font-medium px-3 py-1.5 rounded-lg transition-colors"
            style={{ background: "var(--border)", color: "var(--text-soft)" }}
          >
            {i18n("viewPackagesdeefc55")}
          </button>
        </div>

        {loading && (
          <p className="text-sm" style={{ color: "var(--dim)" }}>
            {i18n("loading33ce417")}
          </p>
        )}

        {error && (
          <p className="text-sm" style={{ color: "var(--danger)" }}>
            {error}
          </p>
        )}

        {!loading && !error && (
          <>
            {/* membership status */}
            <div
              className="rounded-2xl p-5 flex flex-col gap-3"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
            >
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium" style={{ color: "var(--text-soft)" }}>
                  {i18n("membership53bc967")}
                </span>
                {membership?.entitlement_status ? (
                  <StatusBadge status={String(membership.entitlement_status)} />
                ) : null}
              </div>

              {activeSub ? (
                <div className="flex flex-col gap-1">
                  <span className="text-base font-semibold" style={{ color: "var(--text)" }}>
                    {packageLabel(activeSub as Record<string, unknown>)}
                  </span>
                  <span className="text-xs" style={{ color: "var(--dim)" }}>
                    {activeSub.billing_period_snapshot
                      ? `${i18n("billed763fe55")} ${semanticLabel(String(activeSub.billing_period_snapshot), i18n)}`
                      : ""}
                    {activeSub.ends_on ? ` ${i18n("renews241920c")} ${formatDate(uiLocale, activeSub.ends_on as string)}` : ""}
                  </span>
                  {typeof activeSub.price_cents_snapshot === "number" && (
                    <span className="text-sm" style={{ color: "var(--text-soft)" }}>
                      {formatCents(uiLocale, activeSub.price_cents_snapshot)}
                    </span>
                  )}
                </div>
              ) : (
                <p className="text-sm" style={{ color: "var(--dim)" }}>
                  {i18n("noActivePackageSubscription568b2b2")}
                </p>
              )}

              {latestPromo && (
                <div
                  className="rounded-lg px-3 py-2 flex items-center gap-2 mt-1"
                  style={{ background: "var(--border)" }}
                >
                  <span className="text-xs" style={{ color: "var(--dim)" }}>
                    {i18n("campaignCode4099073")}
                  </span>
                  <span className="text-xs font-mono font-semibold" style={{ color: "var(--warning)" }}>
                    {String((latestPromo.promotion_code as Record<string, unknown> | null)?.code ?? latestPromo.code ?? latestPromo.promotion_code_id ?? "—")}
                  </span>
                </div>
              )}
            </div>

            <AccessNotice entitlement={entitlement} />
            <EntitlementCard entitlement={entitlement} />

            <CorporateEnrollmentCard onEnrolled={refreshAfterEnrollment} />

            {/* credits */}
            {hasCredits && (
              <div
                className="rounded-2xl p-5 flex flex-col gap-3"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
              >
                <span className="text-sm font-medium" style={{ color: "var(--text-soft)" }}>
                  {i18n("creditsbfac50d")}
                </span>
                <div className="flex items-end justify-between">
                  <div className="flex flex-col gap-0.5">
                    <span className="text-2xl font-semibold" style={{ color: "var(--text)" }}>
                      {formatCents(uiLocale, finance!.credit_balance)}
                    </span>
                    <span className="text-xs" style={{ color: "var(--dim)" }}>
                      {i18n("availableBalanceadba401")}
                    </span>
                  </div>
                  {totalReferralCents > 0 && (
                    <div className="text-end">
                      <span className="text-sm font-medium" style={{ color: "var(--success)" }}>
                        +{formatCents(uiLocale, totalReferralCents)}
                      </span>
                      <p className="text-xs" style={{ color: "var(--dim)" }}>
                        {i18n("fromReferralsb7146e6")}
                      </p>
                    </div>
                  )}
                </div>

                {referralCredits.length > 0 && (
                  <div className="flex flex-col gap-1 pt-1">
                    {referralCredits.map((entry) => (
                      <div
                        key={String(entry.id)}
                        className="flex items-center justify-between text-xs"
                        style={{ color: "var(--dim)" }}
                      >
                        <span>{String(entry.description ?? i18n("referralReward6fc3bba"))}</span>
                        <span style={{ color: (entry.amount_cents as number) > 0 ? "var(--success)" : "var(--danger)" }}>
                          {(entry.amount_cents as number) > 0 ? "+" : ""}
                          {formatCents(uiLocale, entry.amount_cents as number)}
                        </span>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            )}

            {/* invoices */}
            <div className="flex flex-col gap-3">
              <span className="text-sm font-medium" style={{ color: "var(--text-soft)" }}>
                {i18n("invoices35f8f37")}
              </span>
              {finance!.invoices.length === 0 ? (
                <p className="text-sm" style={{ color: "var(--dim)" }}>
                  {i18n("noInvoicesYet7da80f3")}
                </p>
              ) : (
                <div
                  className="rounded-2xl overflow-auto max-h-[20rem]"
                  style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
                >
                  <table className="w-full min-w-[42rem]" style={{ borderCollapse: "collapse" }}>
                    <thead>
                      <tr style={{ borderBottom: "1px solid var(--border)" }}>
                        {[i18n("numberb7baa1d"), i18n("amount43dc853"), i18n("statusbae7d5b"), i18n("due145caf2"), ""].map((h) => (
                          <th
                            key={h}
                            className="py-2.5 pe-4 text-start text-[11px] font-medium uppercase tracking-wide first:ps-5 last:pe-5 last:text-end"
                            style={{ color: "var(--dim)" }}
                          >
                            {h}
                          </th>
                        ))}
                      </tr>
                    </thead>
                    <tbody className="px-5">
                      {(finance!.invoices as Record<string, unknown>[]).map((inv) => (
                        <InvoiceRow
                          key={String(inv.id)}
                          invoice={inv}
                          token={accessToken!}
                        />
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>

            {/* payment history */}
            {finance!.payments.length > 0 && (
              <div className="flex flex-col gap-3">
                <span className="text-sm font-medium" style={{ color: "var(--text-soft)" }}>
                  {i18n("paymentHistory618b513")}
                </span>
                <div className="flex flex-col gap-1">
                  {(finance!.payments as Record<string, unknown>[]).map((payment) => (
                    <div
                      key={String(payment.id)}
                      className="flex items-center justify-between rounded-xl px-4 py-3"
                      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
                    >
                      <div className="flex flex-col gap-0.5">
                        <span className="text-sm" style={{ color: "var(--text)" }}>
                          {formatCents(uiLocale, 
                            typeof payment.amount_cents === "number" ? payment.amount_cents : null,
                            String(payment.currency ?? i18n("eurd06e073")),
                          )}
                        </span>
                        <span className="text-xs" style={{ color: "var(--dim)" }}>
                          {payment.payment_method
                            ? <SemanticLabel value={String(payment.payment_method)} />
                            : i18n("paymentb41a92b")}
                          {payment.paid_on ? "· " + (formatDate(uiLocale, payment.paid_on as string)) : ""}
                        </span>
                      </div>
                      {payment.payment_status ? (
                        <StatusBadge status={String(payment.payment_status)} />
                      ) : null}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </>
        )}

        {accessToken && !loading && !error ? <MyRefundReceipts /> : null}
      </div>

      {showPackages && finance && (
        <PackageSidePanel
          packages={finance.available_packages as Record<string, unknown>[]}
          onClose={() => setShowPackages(false)}
        />
      )}
    </div>
  );
}
