"use client";







import {useUiLocale} from "@/i18n/use-ui-locale";
import {useUiTranslations} from "@/i18n/ui";
import { localizeError, semanticLabel } from "@/i18n/presentation";
import { SemanticLabel } from "@/components/semantic-label";
import { useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  assignFinancePackage,
  createFinanceInvoice,
  fetchFinanceMember,
  fetchFinancePackages,
  getInvoiceDownloadUrl,
  getInvoiceUploadUrl,
  issueFinanceInvoice,
  recordFinancePayment,
  updateFinanceInvoice,
  voidFinanceInvoice,
  type FinanceRecord,
} from "@/api/finance";
import { useSession } from "@/components/session-provider";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";

function field(record: FinanceRecord | null | undefined, key: string, fallback = "") {
  const value = record?.[key];
  if (value === null || value === undefined) return fallback;
  return String(value);
}

function money(uiLocale: string, cents: unknown) {
  const amount = typeof cents === "number" ? cents : Number(cents ?? 0);
  return new Intl.NumberFormat(uiLocale, { style: "currency", currency: "EUR" }).format(amount / 100);
}

function statusColor(status: string): string {
  if (["active", "paid", "applied"].includes(status)) return "var(--success)";
  if (["overdue", "void", "rejected"].includes(status)) return "var(--primary-strong)";
  if (["pending", "issued", "draft"].includes(status)) return "var(--primary)";
  return "var(--muted)";
}

type Section = "overview" | "invoices" | "payments" | "credits";

export function MemberPanel({
  userId,
  nickname,
  onClose,
}: {
  userId: string;
  nickname: string;
  onClose: () => void;
}) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();

  const [section, setSection] = useState<Section>("overview");
  const [showPaymentForm, setShowPaymentForm] = useState(false);
  const [showInvoiceForm, setShowInvoiceForm] = useState(false);
  const [showAssignForm, setShowAssignForm] = useState(false);
  const [paymentForm, setPaymentForm] = useState({
    amount_cents: "",
    paid_on: "",
    finance_invoice_id: "",
    notes: "",
  });
  const [invoiceForm, setInvoiceForm] = useState({
    amount_cents: "",
    description: "",
    due_date: "",
    membership_package_subscription_id: "",
  });
  const [selectedPackageId, setSelectedPackageId] = useState("");

  const profileQuery = useQuery({
    queryKey: ["admin", "finance", "member-profile", userId],
    enabled: Boolean(token && userId),
    queryFn: () => fetchFinanceMember(token, userId),
  });

  const packagesQuery = useQuery({
    queryKey: ["admin", "finance", "packages"],
    enabled: Boolean(token),
    queryFn: () => fetchFinancePackages(token),
  });

  const profile = profileQuery.data;
  const packages = packagesQuery.data?.packages ?? [];
  const packageSubscriptions = ((profile?.package_subscriptions as FinanceRecord[] | undefined) ?? []).filter(
    (sub) => field(sub, "status") === "active",
  );
  const invoiceNumberById = new Map(
    (((profile?.invoices as FinanceRecord[] | undefined) ?? [])).map((invoice) => [
      field(invoice, "id"),
      field(invoice, "invoice_number", field(invoice, "id")),
    ]),
  );
  const payableInvoices = ((profile?.invoices as FinanceRecord[] | undefined) ?? []).filter((invoice) => {
    const status = field(invoice, "status");
    const balanceDue = typeof invoice.balance_due_cents === "number" ? invoice.balance_due_cents : 0;
    return ["issued", "partially_paid", "overdue"].includes(status) && balanceDue > 0;
  });

  const recordPaymentMutation = useMutation({
    mutationFn: () =>
      recordFinancePayment(token, userId, {
        amount_cents: Math.round(Number(paymentForm.amount_cents || 0) * 100),
        paid_on: paymentForm.paid_on || undefined,
        finance_invoice_id: paymentForm.finance_invoice_id || undefined,
        notes: paymentForm.notes || undefined,
      }),
    onSuccess: async () => {
      setShowPaymentForm(false);
      setPaymentForm({ amount_cents: "", paid_on: "", finance_invoice_id: "", notes: "" });
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "member-profile", userId] });
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "members"] });
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "summary"] });
    },
  });

  const createInvoiceMutation = useMutation({
    mutationFn: () =>
      createFinanceInvoice(token, userId, {
        amount_cents: Math.round(Number(invoiceForm.amount_cents || 0) * 100),
        description: invoiceForm.description || undefined,
        due_date: invoiceForm.due_date || undefined,
        membership_package_subscription_id: invoiceForm.membership_package_subscription_id || undefined,
      }),
    onSuccess: async () => {
      setShowInvoiceForm(false);
      setInvoiceForm({
        amount_cents: "",
        description: "",
        due_date: "",
        membership_package_subscription_id: "",
      });
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "member-profile", userId] });
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "members"] });
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "summary"] });
    },
  });

  const assignPackageMutation = useMutation({
    mutationFn: () => assignFinancePackage(token, userId, { membership_package_id: selectedPackageId }),
    onSuccess: async () => {
      setShowAssignForm(false);
      setSelectedPackageId("");
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "member-profile", userId] });
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "members"] });
    },
  });

  const SECTIONS: { key: Section; label: string }[] = [
    { key: "overview", label: i18n("overview0efc2e6") },
    { key: "invoices", label: i18n("invoices35f8f37") },
    { key: "payments", label: i18n("payments44357ae") },
    { key: "credits", label: i18n("creditsbfac50d") },
  ];

  return (
    <SidePanel
      title={nickname}
      subtitle={i18n("memberFinanceProfile6f16152")}
      onClose={onClose}
    >
      {/* Section pills */}
      <div
        className="flex rounded-full p-0.5 gap-0.5"
        style={{ background: "var(--border)", width: "fit-content" }}
      >
        {SECTIONS.map((s) => (
          <button
            key={s.key}
            className="rounded-full px-3 py-1.5 text-xs font-semibold"
            style={
              section === s.key
                ? { background: "var(--text)", color: "var(--bg)" }
                : { color: "var(--dim)" }
            }
            onClick={() => setSection(s.key)}
            type="button"
          >
            {s.label}
          </button>
        ))}
      </div>

      {profileQuery.isLoading && (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
      )}

      {profile && (
        <>
          {/* Overview */}
          {section === "overview" && (
            <div className="space-y-4">
              {/* Membership summary card */}
              <div className="rounded-[1.5rem] p-4 space-y-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{i18n("membership53bc967")}</p>
                {profile.membership ? (
                  <>
                    <InfoRow label={i18n("statusbae7d5b")} value={semanticLabel(field(profile.membership, "status"), i18n)} color={statusColor(field(profile.membership, "status"))} />
                    <InfoRow label={i18n("expiresa99be3d")} value={field(profile.membership, "expires_on") || "—"} />
                    <InfoRow label={i18n("entitlement8994749")} value={field(profile.membership, "entitlement_status") ? semanticLabel(field(profile.membership, "entitlement_status"), i18n) : "—"} />
                    <InfoRow label={i18n("creditBalance471f025")} value={money(uiLocale, profile.credit_balance)} />
                  </>
                ) : (
                  <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("noMembershipRecord741b5d9")}</p>
                )}
              </div>

              {/* Active package subscription */}
              <div className="rounded-[1.5rem] p-4 space-y-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                <div className="flex items-center justify-between gap-3">
                  <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                    {i18n("packagesd584275")}{(profile.package_subscriptions as FinanceRecord[]).length})
                  </p>
                  <button
                    className="rounded-full px-3 py-1 text-xs font-semibold"
                    style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)", color: "var(--primary)" }}
                    onClick={() => setShowAssignForm((v) => !v)}
                    type="button"
                  >
                    {showAssignForm ? i18n("cancel77dfd21") : i18n("assignPackage90e07f6")}
                  </button>
                </div>

                {showAssignForm && (
                  <div className="space-y-2">
                    <select
                      className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                      style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                      value={selectedPackageId}
                      onChange={(e) => setSelectedPackageId(e.target.value)}
                    >
                      <option value="">{i18n("selectPackage02bf832")}</option>
                      {packages.filter((p) => p.active !== false).map((p) => (
                        <option key={field(p, "id")} value={field(p, "id")}>
                          {field(p, "name", field(p, "code"))}
                        </option>
                      ))}
                    </select>
                    <button
                      className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
                      style={{ background: "var(--text)", color: "var(--bg)" }}
                      disabled={!selectedPackageId || assignPackageMutation.isPending}
                      onClick={() => assignPackageMutation.mutate()}
                      type="button"
                    >
                      {assignPackageMutation.isPending ? i18n("assigning4d16a1a") : i18n("assign2444928")}
                    </button>
                    {assignPackageMutation.error instanceof Error && (
                      <p className="text-xs" style={{ color: "var(--primary-strong)" }}>{localizeError(assignPackageMutation.error, i18n)}</p>
                    )}
                  </div>
                )}

                {(profile.package_subscriptions as FinanceRecord[]).map((sub) => (
                  <div key={field(sub, "id")} className="rounded-[1rem] px-3 py-2" style={{ background: "var(--panel)" }}>
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                        {field(sub, "package_code_snapshot")}
                      </span>
                      <span
                        className="rounded-full px-2 py-0.5 text-xs font-semibold"
                        style={{ color: statusColor(field(sub, "status")), background: "color-mix(in srgb, var(--bg) 30%, transparent)" }}
                      >
                        <SemanticLabel value={field(sub, "status")} />
                      </span>
                    </div>
                    <p className="text-xs mt-0.5" style={{ color: "var(--dim)" }}>
                      {field(sub, "billing_period_snapshot")} · {money(uiLocale, sub.price_cents_snapshot)} {i18n("ends74f5b4d")} {field(sub, "ends_on") || "—"}
                    </p>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Invoices */}
          {section === "invoices" && (
            <div className="space-y-3">
              <div className="flex items-center justify-between gap-3">
                <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                  {i18n("invoices523da66")}{(profile.invoices as FinanceRecord[]).length})
                </p>
                <button
                  className="rounded-full px-3 py-1 text-xs font-semibold"
                  style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)", color: "var(--primary)" }}
                  onClick={() => setShowInvoiceForm((v) => !v)}
                  type="button"
                >
                  {showInvoiceForm ? i18n("cancel77dfd21") : i18n("newInvoicefa5b135")}
                </button>
              </div>

              {showInvoiceForm && (
                <div className="rounded-[1.5rem] p-4 space-y-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                  <FormField label={i18n("amountEur2dc6463")}>
                    <input
                      className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                      style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                      type="number"
                      value={invoiceForm.amount_cents}
                      onChange={(e) => setInvoiceForm({ ...invoiceForm, amount_cents: e.target.value })}
                    />
                  </FormField>
                  <FormField label={i18n("packageSubscriptionOptional9d7a12d")}>
                    <select
                      className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                      style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                      value={invoiceForm.membership_package_subscription_id}
                      onChange={(e) => {
                        const membership_package_subscription_id = e.target.value;
                        const subscription = packageSubscriptions.find(
                          (sub) => field(sub, "id") === membership_package_subscription_id,
                        );
                        const priceCents =
                          typeof subscription?.price_cents_snapshot === "number" ? subscription.price_cents_snapshot : null;
                        const code = field(subscription, "package_code_snapshot");

                        setInvoiceForm({
                          ...invoiceForm,
                          membership_package_subscription_id,
                          amount_cents: priceCents !== null ? String(priceCents / 100) : invoiceForm.amount_cents,
                          description: code ? i18n("package5544677") + (code) : invoiceForm.description,
                        });
                      }}
                    >
                      <option value="">{i18n("noPackageLink7149c0f")}</option>
                      {packageSubscriptions.map((sub) => (
                        <option key={field(sub, "id")} value={field(sub, "id")}>
                          {field(sub, "package_code_snapshot", i18n("package7431e3d"))} · {money(uiLocale, sub.price_cents_snapshot)}
                        </option>
                      ))}
                    </select>
                  </FormField>
                  <FormField label={i18n("description55f8ebc")}>
                    <input
                      className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                      style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                      value={invoiceForm.description}
                      onChange={(e) => setInvoiceForm({ ...invoiceForm, description: e.target.value })}
                    />
                  </FormField>
                  <FormField label={i18n("dueDate4c1aeeb")}>
                    <input
                      className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                      style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                      type="date"
                      value={invoiceForm.due_date}
                      onChange={(e) => setInvoiceForm({ ...invoiceForm, due_date: e.target.value })}
                    />
                  </FormField>
                  <button
                    className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
                    style={{ background: "var(--text)", color: "var(--bg)" }}
                    disabled={
                      (!invoiceForm.amount_cents && !invoiceForm.membership_package_subscription_id) ||
                      createInvoiceMutation.isPending
                    }
                    onClick={() => createInvoiceMutation.mutate()}
                    type="button"
                  >
                    {createInvoiceMutation.isPending ? i18n("creating94d7d8e") : i18n("createInvoicea0567cf")}
                  </button>
                  {createInvoiceMutation.error instanceof Error && (
                    <p className="text-xs" style={{ color: "var(--primary-strong)" }}>{localizeError(createInvoiceMutation.error, i18n)}</p>
                  )}
                </div>
              )}

              {(profile.invoices as FinanceRecord[]).length === 0 ? (
                <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("noInvoicesYet7da80f3")}</p>
              ) : (
                <div className="space-y-2">
                  {(profile.invoices as FinanceRecord[]).map((inv) => (
                    <InvoiceCard
                      key={field(inv, "id")}
                      invoice={inv}
                      token={token}
                      onUploaded={() =>
                        queryClient.invalidateQueries({
                          queryKey: ["admin", "finance", "member-profile", userId],
                        })
                      }
                    />
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Payments */}
          {section === "payments" && (
            <div className="space-y-3">
              <div className="flex items-center justify-between gap-3">
                <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                  {i18n("payments89038de")}{(profile.payments as FinanceRecord[]).length})
                </p>
                <button
                  className="rounded-full px-3 py-1 text-xs font-semibold"
                  style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)", color: "var(--primary)" }}
                  onClick={() => setShowPaymentForm((v) => !v)}
                  type="button"
                >
                  {showPaymentForm ? i18n("cancel77dfd21") : i18n("recordPayment3830944")}
                </button>
              </div>

              {showPaymentForm && (
                <div className="rounded-[1.5rem] p-4 space-y-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                  <FormField label={i18n("amountEur2dc6463")}>
                    <input
                      className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                      style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                      type="number"
                      value={paymentForm.amount_cents}
                      onChange={(e) => setPaymentForm({ ...paymentForm, amount_cents: e.target.value })}
                    />
                  </FormField>
                  <FormField label={i18n("invoiceOptionalaef614c")}>
                    <select
                      className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                      style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                      value={paymentForm.finance_invoice_id}
                      onChange={(e) => {
                        const finance_invoice_id = e.target.value;
                        const invoice = payableInvoices.find((item) => field(item, "id") === finance_invoice_id);
                        const balanceDue =
                          typeof invoice?.balance_due_cents === "number" ? invoice.balance_due_cents : null;

                        setPaymentForm({
                          ...paymentForm,
                          finance_invoice_id,
                          amount_cents: balanceDue !== null ? String(balanceDue / 100) : paymentForm.amount_cents,
                        });
                      }}
                    >
                      <option value="">{i18n("noInvoiceLink0b4810f")}</option>
                      {payableInvoices.map((invoice) => (
                        <option key={field(invoice, "id")} value={field(invoice, "id")}>
                          {field(invoice, "invoice_number", i18n("invoicef9f3881"))} · {money(uiLocale, invoice.balance_due_cents)} {i18n("due30cdf73")}
                        </option>
                      ))}
                    </select>
                  </FormField>
                  <FormField label={i18n("paidOnfca3213")}>
                    <input
                      className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                      style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                      type="date"
                      value={paymentForm.paid_on}
                      onChange={(e) => setPaymentForm({ ...paymentForm, paid_on: e.target.value })}
                    />
                  </FormField>
                  <FormField label={i18n("notesOptional4d56ca9")}>
                    <input
                      className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                      style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                      value={paymentForm.notes}
                      onChange={(e) => setPaymentForm({ ...paymentForm, notes: e.target.value })}
                    />
                  </FormField>
                  <button
                    className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
                    style={{ background: "var(--text)", color: "var(--bg)" }}
                    disabled={!paymentForm.amount_cents || recordPaymentMutation.isPending}
                    onClick={() => recordPaymentMutation.mutate()}
                    type="button"
                  >
                    {recordPaymentMutation.isPending ? i18n("recording72f9eb4") : i18n("recordPayment86e5632")}
                  </button>
                  {recordPaymentMutation.error instanceof Error && (
                    <p className="text-xs" style={{ color: "var(--primary-strong)" }}>{localizeError(recordPaymentMutation.error, i18n)}</p>
                  )}
                </div>
              )}

              {(profile.payments as FinanceRecord[]).length === 0 ? (
                <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("noPaymentsRecordedc84cf39")}</p>
              ) : (
                <div className="space-y-2">
                  {(profile.payments as FinanceRecord[]).map((pay) => (
                    <div key={field(pay, "id")} className="rounded-[1.2rem] px-4 py-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                      <div className="flex items-center justify-between gap-3">
                        <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                          {money(uiLocale, pay.amount_cents)}
                        </span>
                        <span className="text-xs" style={{ color: "var(--muted)" }}>
                          {field(pay, "paid_on")}
                          {field(pay, "finance_invoice_id")
                            ? i18n("linkedToInvoice541dca8") + (invoiceNumberById.get(field(pay, "finance_invoice_id")) ?? field(pay, "finance_invoice_id"))
                            : ""}
                        </span>
                      </div>
                      {field(pay, "notes") && (
                        <p className="text-xs mt-0.5" style={{ color: "var(--dim)" }}>{field(pay, "notes")}</p>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Credits */}
          {section === "credits" && (
            <div className="space-y-3">
              <div className="flex items-center justify-between gap-3">
                <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                  {i18n("creditLedger88b2bbb")}{(profile.credit_ledger_entries as FinanceRecord[]).length})
                </p>
                <span className="text-sm font-semibold" style={{ color: "var(--success)" }}>
                  {i18n("balance802dc02")} {money(uiLocale, profile.credit_balance)}
                </span>
              </div>

              {(profile.credit_ledger_entries as FinanceRecord[]).length === 0 ? (
                <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("noCreditEntries0c8905b")}</p>
              ) : (
                <div className="space-y-2">
                  {(profile.credit_ledger_entries as FinanceRecord[]).map((entry) => (
                    <div key={field(entry, "id")} className="rounded-[1.2rem] px-4 py-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                      <div className="flex items-center justify-between gap-3">
                        <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                          {money(uiLocale, entry.amount_cents)}
                        </span>
                        <span className="text-xs font-semibold" style={{ color: statusColor(field(entry, "status")) }}>
                          <SemanticLabel value={field(entry, "status")} />
                        </span>
                      </div>
                      {field(entry, "description") && (
                        <p className="text-xs mt-0.5" style={{ color: "var(--dim)" }}>{field(entry, "description")}</p>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}
        </>
      )}
    </SidePanel>
  );
}

// ── InvoiceCard ───────────────────────────────────────────────────────────────

function InvoiceCard({
  invoice,
  token,
  onUploaded,
}: {
  invoice: FinanceRecord;
  token: string;
  onUploaded: () => void;
}) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const invoiceId = field(invoice, "id");
  const status = field(invoice, "status");
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [downloading, setDownloading] = useState(false);
  const [editing, setEditing] = useState(false);
  const [editDueDate, setEditDueDate] = useState(field(invoice, "due_date"));
  const [editNotes, setEditNotes] = useState(field(invoice, "notes"));
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [actioning, setActioning] = useState(false);
  const invoiceParams = (invoice.params as Record<string, string> | null) ?? {};
  const hasFile = Boolean(invoiceParams.file_key);

  async function handleIssue() {
    setActioning(true);
    try {
      await issueFinanceInvoice(token, invoiceId);
      onUploaded();
    } finally {
      setActioning(false);
    }
  }

  async function handleVoid() {
    if (!confirm(i18n("voidThisInvoiceThisCannotBeUndone571b60e"))) return;
    setActioning(true);
    try {
      await voidFinanceInvoice(token, invoiceId);
      onUploaded();
    } finally {
      setActioning(false);
    }
  }

  async function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    setUploadError(null);
    try {
      const { upload_url, content_type } = await getInvoiceUploadUrl(
        token,
        invoiceId,
        file.name,
        file.type || "application/octet-stream",
      );
      const res = await fetch(upload_url, {
        method: "PUT",
        headers: { "Content-Type": content_type },
        body: file,
      });
      if (!res.ok) throw new Error(i18n("uploadFailed7c67e1c") + (res.status));
      onUploaded();
    } catch (err) {
      setUploadError(err instanceof Error ? localizeError(err, i18n) : i18n("uploadFailedad0d060"));
    } finally {
      setUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  }

  async function handleDownload() {
    setDownloading(true);
    try {
      const { download_url, file_name } = await getInvoiceDownloadUrl(token, invoiceId);
      const a = document.createElement("a");
      a.href = download_url;
      a.download = file_name;
      a.target = "_blank";
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
    } finally {
      setDownloading(false);
    }
  }

  async function handleSaveEdit() {
    setSaving(true);
    setSaveError(null);
    try {
      await updateFinanceInvoice(token, invoiceId, {
        due_date: editDueDate || undefined,
        notes: editNotes || undefined,
      });
      setEditing(false);
      onUploaded();
    } catch (err) {
      setSaveError(err instanceof Error ? localizeError(err, i18n) : i18n("saveFailed0a44446"));
    } finally {
      setSaving(false);
    }
  }

  return (
    <div
      className="rounded-[1.2rem] px-4 py-3 space-y-2"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      <div className="flex items-center justify-between gap-3">
        <div className="space-y-0.5">
          <p className="text-xs font-semibold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>
            {field(invoice, "invoice_number", invoiceId)}
          </p>
          <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {money(uiLocale, invoice.total_cents)}
          </span>
        </div>
        <div className="flex items-center gap-2">
          <span
            className="text-xs font-semibold"
            style={{ color: statusColor(status) }}
          >
            <SemanticLabel value={status} />
          </span>

          {status === "draft" && (
            <button
              type="button"
              onClick={handleIssue}
              disabled={actioning}
              className="rounded-full px-2 py-0.5 text-xs font-semibold disabled:opacity-50 transition-opacity hover:opacity-80"
              style={{ background: "color-mix(in srgb, var(--success) 15%, transparent)", color: "var(--success)", border: "1px solid color-mix(in srgb, var(--success) 30%, transparent)" }}
            >
              {actioning ? "…" : i18n("issue73781a1")}
            </button>
          )}

          {status !== "void" && status !== "paid" && (
            <button
              type="button"
              onClick={handleVoid}
              disabled={actioning}
              className="rounded-full px-2 py-0.5 text-xs font-semibold disabled:opacity-50 transition-opacity hover:opacity-80"
              style={{ background: "color-mix(in srgb, var(--primary-strong) 10%, transparent)", color: "var(--primary-strong)", border: "1px solid color-mix(in srgb, var(--primary-strong) 25%, transparent)" }}
            >
              {i18n("void207c7c0")}
            </button>
          )}

          <button
            type="button"
            onClick={() => {
              setEditing((v) => !v);
              setSaveError(null);
            }}
            className="text-xs hover:opacity-70 transition-opacity"
            style={{ color: "var(--dim)" }}
          >
            {editing ? i18n("cancel77dfd21") : i18n("edit5301648")}
          </button>
        </div>
      </div>

      {/* Notes prominent display */}
      {!editing && (
        <div className="space-y-0.5">
          {field(invoice, "notes") ? (
            <p className="text-sm font-medium" style={{ color: "var(--text-soft)" }}>
              {field(invoice, "notes")}
            </p>
          ) : (
            <p className="text-xs italic" style={{ color: "var(--dim)" }}>{i18n("noDescriptionf354c94")}</p>
          )}
          <p className="text-xs" style={{ color: "var(--dim)" }}>
            {i18n("due7513f96")} {field(invoice, "due_date") || "—"}
          </p>
        </div>
      )}

      {/* Inline edit */}
      {editing && (
        <div className="space-y-2 pt-1">
          <div className="space-y-1">
            <label className="text-xs font-semibold uppercase tracking-[0.15em]" style={{ color: "var(--dim)" }}>
              {i18n("description55f8ebc")}
            </label>
            <input
              type="text"
              value={editNotes}
              onChange={(e) => setEditNotes(e.target.value)}
              placeholder={i18n("invoiceDescription4d26246")}
              className="w-full rounded-xl px-3 py-1.5 text-sm"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border-strong)", color: "var(--text)" }}
            />
          </div>
          <div className="space-y-1">
            <label className="text-xs font-semibold uppercase tracking-[0.15em]" style={{ color: "var(--dim)" }}>
              {i18n("dueDate4c1aeeb")}
            </label>
            <input
              type="date"
              value={editDueDate}
              onChange={(e) => setEditDueDate(e.target.value)}
              className="w-full rounded-xl px-3 py-1.5 text-sm"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border-strong)", color: "var(--text)" }}
            />
          </div>
          {saveError && <p className="text-xs" style={{ color: "var(--primary-strong)" }}>{saveError}</p>}
          <button
            type="button"
            onClick={handleSaveEdit}
            disabled={saving}
            className="rounded-full px-3 py-1 text-xs font-semibold disabled:opacity-50 transition-opacity hover:opacity-80"
            style={{ background: "color-mix(in srgb, var(--success) 15%, transparent)", color: "var(--success)", border: "1px solid color-mix(in srgb, var(--success) 30%, transparent)" }}
          >
            {saving ? i18n("saving56a2285") : i18n("saveefc007a")}
          </button>
        </div>
      )}

      {/* File actions */}
      <div className="flex items-center gap-2 pt-1">
        <input
          ref={fileInputRef}
          type="file"
          accept="image/*,.pdf"
          className="hidden"
          onChange={handleFileChange}
        />
        <button
          type="button"
          onClick={() => fileInputRef.current?.click()}
          disabled={uploading}
          className="rounded-full px-2.5 py-1 text-xs font-semibold disabled:opacity-50 transition-opacity hover:opacity-70"
          style={{ background: "var(--border)", color: "var(--text-soft)", border: "1px solid var(--border-strong)" }}
        >
          {uploading ? i18n("uploadingd921a79") : hasFile ? i18n("replaceFile6d45b8c") : i18n("uploadFile503a3d8")}
        </button>

        {hasFile && (
          <button
            type="button"
            onClick={handleDownload}
            disabled={downloading}
            className="rounded-full px-2.5 py-1 text-xs font-semibold disabled:opacity-50 transition-opacity hover:opacity-70"
            style={{ background: "color-mix(in srgb, var(--success) 10%, transparent)", color: "var(--success)", border: "1px solid color-mix(in srgb, var(--success) 25%, transparent)" }}
          >
            {downloading ? "…" : i18n("downloada479c9c")}
          </button>
        )}

        {invoiceParams.file_name && (
          <span className="text-xs truncate max-w-[120px]" style={{ color: "var(--dim)" }}>
            {invoiceParams.file_name}
          </span>
        )}
      </div>

      {uploadError && (
        <p className="text-xs" style={{ color: "var(--primary-strong)" }}>
          {uploadError}
        </p>
      )}
    </div>
  );
}

function InfoRow({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <div className="flex items-center justify-between gap-4 text-sm">
      <span style={{ color: "var(--dim)" }}>{label}</span>
      <span className="font-semibold" style={{ color: color ?? "var(--text)" }}>{value || "—"}</span>
    </div>
  );
}

function FormField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block space-y-1">
      <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{label}</span>
      {children}
    </label>
  );
}
