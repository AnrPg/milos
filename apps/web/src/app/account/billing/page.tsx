"use client";

import { useEffect, useRef, useState } from "react";

import { fetchMyFinance, getMyInvoiceDownloadUrl, type MyFinanceData } from "@/api/my-finance";
import { useSession } from "@/components/session-provider";

// ─── helpers ──────────────────────────────────────────────────────────────────

function formatCents(cents: number | null | undefined, currency = "EUR") {
  if (cents == null) return "—";
  return new Intl.NumberFormat("en-EU", {
    style: "currency",
    currency: (currency as string) || "EUR",
    minimumFractionDigits: 2,
  }).format(cents / 100);
}

function formatDate(value: string | null | undefined) {
  if (!value) return "—";
  return new Date(value).toLocaleDateString("en-GB", {
    day: "2-digit",
    month: "short",
    year: "numeric",
  });
}

const STATUS_COLORS: Record<string, string> = {
  issued: "var(--success)",
  partially_paid: "var(--warning)",
  paid: "var(--info)",
  overdue: "var(--danger)",
  void: "var(--dim)",
  active: "var(--success)",
  inactive: "var(--dim)",
  cancelled: "var(--danger)",
  pending: "var(--warning)",
};

function StatusBadge({ status }: { status: string }) {
  const color = STATUS_COLORS[status] ?? "var(--muted)";
  return (
    <span
      className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wide"
      style={{ background: `${color}22`, color }}
    >
      <span
        className="inline-block w-1.5 h-1.5 rounded-full"
        style={{ background: color }}
      />
      {status.replace(/_/g, " ")}
    </span>
  );
}

// ─── side panel ───────────────────────────────────────────────────────────────

function PackageSidePanel({
  packages,
  onClose,
}: {
  packages: Record<string, unknown>[];
  onClose: () => void;
}) {
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
          borderLeft: "1px solid var(--border)",
          padding: "2rem 1.5rem",
          gap: "1.25rem",
        }}
      >
        <div className="flex items-center justify-between">
          <h2 className="text-base font-semibold" style={{ color: "var(--text)" }}>
            Available Packages
          </h2>
          <button
            type="button"
            onClick={onClose}
            className="text-sm"
            style={{ color: "var(--dim)" }}
          >
            ✕ Close
          </button>
        </div>

        {packages.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>
            No packages available.
          </p>
        ) : (
          packages.map((pkg) => {
            const name = String(pkg.name ?? pkg.code ?? "Package");
            const family = pkg.family ? String(pkg.family) : null;
            const billing = pkg.billing_period ? String(pkg.billing_period) : null;
            const price = typeof pkg.base_price_cents === "number" ? pkg.base_price_cents : null;
            const currency = String(pkg.currency ?? "EUR");
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
                      Unavailable
                    </span>
                  )}
                </div>
                {family && (
                  <span className="text-xs" style={{ color: "var(--dim)" }}>
                    {family}
                    {billing ? ` · ${billing}` : ""}
                  </span>
                )}
                {price != null && (
                  <span className="text-sm font-medium" style={{ color: "var(--text-soft)" }}>
                    {formatCents(price, currency)}
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
  if (cents <= 0) return null;
  return (
    <span
      className="inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-semibold"
      style={{
        background: "color-mix(in srgb, var(--danger) 12%, transparent)",
        color: "var(--danger)",
      }}
    >
      {formatCents(cents)} due
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
      <td className="py-3 pr-4 text-sm font-mono" style={{ color: "var(--text-soft)" }}>
        {String(invoice.invoice_number ?? "—")}
      </td>
      <td className="py-3 pr-4 text-sm" style={{ color: "var(--text)" }}>
        {formatCents(
          typeof invoice.total_cents === "number" ? invoice.total_cents : null,
          String(invoice.currency ?? "EUR"),
        )}
      </td>
      <td className="py-3 pr-4">
        <div className="flex items-center gap-2 flex-wrap">
          <StatusBadge status={String(invoice.status ?? "")} />
          <BalanceDueBadge cents={balanceDueCents} />
        </div>
      </td>
      <td className="py-3 pr-4 text-sm" style={{ color: "var(--dim)" }}>
        {formatDate(invoice.due_date as string | null)}
      </td>
      <td className="py-3 text-right">
        {hasFile ? (
          <button
            type="button"
            onClick={() => void handleDownload()}
            disabled={downloading}
            className="text-xs font-medium transition-opacity"
            style={{ color: "var(--primary-strong)", opacity: downloading ? 0.5 : 1 }}
          >
            {downloading ? "…" : "Download"}
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
  const { tokens } = useSession();
  const accessToken = tokens?.access_token ?? null;

  const [finance, setFinance] = useState<MyFinanceData | null>(null);
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

    fetchMyFinance(accessToken)
      .then((data) => {
        if (!cancelled) {
          setFinance(data);
          setLoading(false);
        }
      })
      .catch(() => {
        if (!cancelled) {
          setError("Could not load billing information.");
          setLoading(false);
        }
      });

    return () => {
      cancelled = true;
    };
  }, [accessToken]);

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
          <h1 className="text-xl font-semibold" style={{ color: "var(--text)" }}>
            Billing
          </h1>
          <button
            type="button"
            onClick={() => setShowPackages(true)}
            className="text-xs font-medium px-3 py-1.5 rounded-lg transition-colors"
            style={{ background: "var(--border)", color: "var(--text-soft)" }}
          >
            View packages
          </button>
        </div>

        {loading && (
          <p className="text-sm" style={{ color: "var(--dim)" }}>
            Loading…
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
                  Membership
                </span>
                {membership?.entitlement_status ? (
                  <StatusBadge status={String(membership.entitlement_status)} />
                ) : null}
              </div>

              {activeSub ? (
                <div className="flex flex-col gap-1">
                  <span className="text-base font-semibold" style={{ color: "var(--text)" }}>
                    {String(activeSub.package_code_snapshot ?? activeSub.package_family_snapshot ?? "—")}
                  </span>
                  <span className="text-xs" style={{ color: "var(--dim)" }}>
                    {activeSub.billing_period_snapshot
                      ? `Billed ${String(activeSub.billing_period_snapshot)}`
                      : ""}
                    {activeSub.ends_on ? ` · renews ${formatDate(activeSub.ends_on as string)}` : ""}
                  </span>
                  {typeof activeSub.price_cents_snapshot === "number" && (
                    <span className="text-sm" style={{ color: "var(--text-soft)" }}>
                      {formatCents(activeSub.price_cents_snapshot)}
                    </span>
                  )}
                </div>
              ) : (
                <p className="text-sm" style={{ color: "var(--dim)" }}>
                  No active package subscription.
                </p>
              )}

              {latestPromo && (
                <div
                  className="rounded-lg px-3 py-2 flex items-center gap-2 mt-1"
                  style={{ background: "var(--border)" }}
                >
                  <span className="text-xs" style={{ color: "var(--dim)" }}>
                    Campaign code
                  </span>
                  <span className="text-xs font-mono font-semibold" style={{ color: "var(--warning)" }}>
                    {String((latestPromo.promotion_code as Record<string, unknown> | null)?.code ?? latestPromo.code ?? latestPromo.promotion_code_id ?? "—")}
                  </span>
                </div>
              )}
            </div>

            {/* credits */}
            {hasCredits && (
              <div
                className="rounded-2xl p-5 flex flex-col gap-3"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
              >
                <span className="text-sm font-medium" style={{ color: "var(--text-soft)" }}>
                  Credits
                </span>
                <div className="flex items-end justify-between">
                  <div className="flex flex-col gap-0.5">
                    <span className="text-2xl font-semibold" style={{ color: "var(--text)" }}>
                      {formatCents(finance!.credit_balance)}
                    </span>
                    <span className="text-xs" style={{ color: "var(--dim)" }}>
                      Available balance
                    </span>
                  </div>
                  {totalReferralCents > 0 && (
                    <div className="text-right">
                      <span className="text-sm font-medium" style={{ color: "var(--success)" }}>
                        +{formatCents(totalReferralCents)}
                      </span>
                      <p className="text-xs" style={{ color: "var(--dim)" }}>
                        from referrals
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
                        <span>{String(entry.description ?? "Referral reward")}</span>
                        <span style={{ color: (entry.amount_cents as number) > 0 ? "var(--success)" : "var(--danger)" }}>
                          {(entry.amount_cents as number) > 0 ? "+" : ""}
                          {formatCents(entry.amount_cents as number)}
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
                Invoices
              </span>
              {finance!.invoices.length === 0 ? (
                <p className="text-sm" style={{ color: "var(--dim)" }}>
                  No invoices yet.
                </p>
              ) : (
                <div
                  className="rounded-2xl overflow-auto max-h-[20rem]"
                  style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
                >
                  <table className="w-full min-w-[42rem]" style={{ borderCollapse: "collapse" }}>
                    <thead>
                      <tr style={{ borderBottom: "1px solid var(--border)" }}>
                        {["Number", "Amount", "Status", "Due", ""].map((h) => (
                          <th
                            key={h}
                            className="py-2.5 pr-4 text-left text-[11px] font-medium uppercase tracking-wide first:pl-5 last:pr-5 last:text-right"
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
                  Payment history
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
                          {formatCents(
                            typeof payment.amount_cents === "number" ? payment.amount_cents : null,
                            String(payment.currency ?? "EUR"),
                          )}
                        </span>
                        <span className="text-xs" style={{ color: "var(--dim)" }}>
                          {payment.payment_method
                            ? String(payment.payment_method).replace(/_/g, " ")
                            : "Payment"}
                          {payment.paid_on ? ` · ${formatDate(payment.paid_on as string)}` : ""}
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
