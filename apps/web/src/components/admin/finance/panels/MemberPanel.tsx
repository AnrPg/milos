"use client";

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
  updateFinanceMember,
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

function money(cents: unknown) {
  const amount = typeof cents === "number" ? cents : Number(cents ?? 0);
  return new Intl.NumberFormat("en-GB", { style: "currency", currency: "EUR" }).format(amount / 100);
}

function statusColor(status: string): string {
  if (["active", "paid", "applied"].includes(status)) return "#4db89c";
  if (["overdue", "void", "rejected"].includes(status)) return "#e07a5f";
  if (["pending", "issued", "draft"].includes(status)) return "#d95d39";
  return "#8888aa";
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
  const { tokens } = useSession();
  const token = tokens?.access_token!;
  const queryClient = useQueryClient();

  const [section, setSection] = useState<Section>("overview");
  const [showPaymentForm, setShowPaymentForm] = useState(false);
  const [showInvoiceForm, setShowInvoiceForm] = useState(false);
  const [showAssignForm, setShowAssignForm] = useState(false);
  const [paymentForm, setPaymentForm] = useState({ amount_cents: "", paid_on: "", notes: "" });
  const [invoiceForm, setInvoiceForm] = useState({ amount_cents: "", description: "", due_date: "" });
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

  const recordPaymentMutation = useMutation({
    mutationFn: () =>
      recordFinancePayment(token, userId, {
        amount_cents: Math.round(Number(paymentForm.amount_cents || 0) * 100),
        paid_on: paymentForm.paid_on || undefined,
        notes: paymentForm.notes || undefined,
      }),
    onSuccess: async () => {
      setShowPaymentForm(false);
      setPaymentForm({ amount_cents: "", paid_on: "", notes: "" });
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "member-profile", userId] });
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "members"] });
    },
  });

  const createInvoiceMutation = useMutation({
    mutationFn: () =>
      createFinanceInvoice(token, userId, {
        amount_cents: Math.round(Number(invoiceForm.amount_cents || 0) * 100),
        description: invoiceForm.description || undefined,
        due_date: invoiceForm.due_date || undefined,
      }),
    onSuccess: async () => {
      setShowInvoiceForm(false);
      setInvoiceForm({ amount_cents: "", description: "", due_date: "" });
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "member-profile", userId] });
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
    { key: "overview", label: "Overview" },
    { key: "invoices", label: "Invoices" },
    { key: "payments", label: "Payments" },
    { key: "credits", label: "Credits" },
  ];

  return (
    <SidePanel
      title={nickname}
      subtitle="Member finance profile"
      onClose={onClose}
    >
      {/* Section pills */}
      <div
        className="flex rounded-full p-0.5 gap-0.5"
        style={{ background: "#1a1a28", width: "fit-content" }}
      >
        {SECTIONS.map((s) => (
          <button
            key={s.key}
            className="rounded-full px-3 py-1.5 text-xs font-semibold"
            style={
              section === s.key
                ? { background: "#F0EDF8", color: "#0A0A0F" }
                : { color: "#55556a" }
            }
            onClick={() => setSection(s.key)}
            type="button"
          >
            {s.label}
          </button>
        ))}
      </div>

      {profileQuery.isLoading && (
        <p className="text-sm" style={{ color: "#55556a" }}>Loading…</p>
      )}

      {profile && (
        <>
          {/* Overview */}
          {section === "overview" && (
            <div className="space-y-4">
              {/* Membership summary card */}
              <div className="rounded-[1.5rem] p-4 space-y-3" style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}>
                <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>Membership</p>
                {profile.membership ? (
                  <>
                    <InfoRow label="Status" value={field(profile.membership, "status")} color={statusColor(field(profile.membership, "status"))} />
                    <InfoRow label="Expires" value={field(profile.membership, "expires_on") || "—"} />
                    <InfoRow label="Entitlement" value={field(profile.membership, "entitlement_status") || "—"} />
                    <InfoRow label="Credit balance" value={money(profile.credit_balance)} />
                  </>
                ) : (
                  <p className="text-sm" style={{ color: "#55556a" }}>No membership record.</p>
                )}
              </div>

              {/* Active package subscription */}
              <div className="rounded-[1.5rem] p-4 space-y-3" style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}>
                <div className="flex items-center justify-between gap-3">
                  <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                    Packages ({(profile.package_subscriptions as FinanceRecord[]).length})
                  </p>
                  <button
                    className="rounded-full px-3 py-1 text-xs font-semibold"
                    style={{ background: "rgba(217,93,57,0.1)", border: "1px solid rgba(217,93,57,0.2)", color: "#d95d39" }}
                    onClick={() => setShowAssignForm((v) => !v)}
                    type="button"
                  >
                    {showAssignForm ? "Cancel" : "+ Assign package"}
                  </button>
                </div>

                {showAssignForm && (
                  <div className="space-y-2">
                    <select
                      className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                      style={{ background: "#111118", border: "1px solid #1a1a28", color: "#F0EDF8" }}
                      value={selectedPackageId}
                      onChange={(e) => setSelectedPackageId(e.target.value)}
                    >
                      <option value="">Select package…</option>
                      {packages.filter((p) => p.active !== false).map((p) => (
                        <option key={field(p, "id")} value={field(p, "id")}>
                          {field(p, "name", field(p, "code"))}
                        </option>
                      ))}
                    </select>
                    <button
                      className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
                      style={{ background: "#F0EDF8", color: "#0A0A0F" }}
                      disabled={!selectedPackageId || assignPackageMutation.isPending}
                      onClick={() => assignPackageMutation.mutate()}
                      type="button"
                    >
                      {assignPackageMutation.isPending ? "Assigning…" : "Assign"}
                    </button>
                    {assignPackageMutation.error instanceof Error && (
                      <p className="text-xs" style={{ color: "#e07a5f" }}>{assignPackageMutation.error.message}</p>
                    )}
                  </div>
                )}

                {(profile.package_subscriptions as FinanceRecord[]).map((sub) => (
                  <div key={field(sub, "id")} className="rounded-[1rem] px-3 py-2" style={{ background: "#111118" }}>
                    <div className="flex items-center justify-between gap-2">
                      <span className="text-sm font-semibold" style={{ color: "#F0EDF8" }}>
                        {field(sub, "package_code_snapshot")}
                      </span>
                      <span
                        className="rounded-full px-2 py-0.5 text-xs font-semibold"
                        style={{ color: statusColor(field(sub, "status")), background: "rgba(0,0,0,0.3)" }}
                      >
                        {field(sub, "status")}
                      </span>
                    </div>
                    <p className="text-xs mt-0.5" style={{ color: "#55556a" }}>
                      {field(sub, "billing_period_snapshot")} · {money(sub.price_cents_snapshot)} · ends {field(sub, "ends_on") || "—"}
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
                <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                  Invoices ({(profile.invoices as FinanceRecord[]).length})
                </p>
                <button
                  className="rounded-full px-3 py-1 text-xs font-semibold"
                  style={{ background: "rgba(217,93,57,0.1)", border: "1px solid rgba(217,93,57,0.2)", color: "#d95d39" }}
                  onClick={() => setShowInvoiceForm((v) => !v)}
                  type="button"
                >
                  {showInvoiceForm ? "Cancel" : "+ New invoice"}
                </button>
              </div>

              {showInvoiceForm && (
                <div className="rounded-[1.5rem] p-4 space-y-3" style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}>
                  <FormField label="Amount (EUR)">
                    <input
                      className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                      style={{ background: "#111118", border: "1px solid #1a1a28", color: "#F0EDF8" }}
                      type="number"
                      value={invoiceForm.amount_cents}
                      onChange={(e) => setInvoiceForm({ ...invoiceForm, amount_cents: e.target.value })}
                    />
                  </FormField>
                  <FormField label="Description">
                    <input
                      className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                      style={{ background: "#111118", border: "1px solid #1a1a28", color: "#F0EDF8" }}
                      value={invoiceForm.description}
                      onChange={(e) => setInvoiceForm({ ...invoiceForm, description: e.target.value })}
                    />
                  </FormField>
                  <FormField label="Due date">
                    <input
                      className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                      style={{ background: "#111118", border: "1px solid #1a1a28", color: "#F0EDF8" }}
                      type="date"
                      value={invoiceForm.due_date}
                      onChange={(e) => setInvoiceForm({ ...invoiceForm, due_date: e.target.value })}
                    />
                  </FormField>
                  <button
                    className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
                    style={{ background: "#F0EDF8", color: "#0A0A0F" }}
                    disabled={!invoiceForm.amount_cents || createInvoiceMutation.isPending}
                    onClick={() => createInvoiceMutation.mutate()}
                    type="button"
                  >
                    {createInvoiceMutation.isPending ? "Creating…" : "Create invoice"}
                  </button>
                  {createInvoiceMutation.error instanceof Error && (
                    <p className="text-xs" style={{ color: "#e07a5f" }}>{createInvoiceMutation.error.message}</p>
                  )}
                </div>
              )}

              {(profile.invoices as FinanceRecord[]).length === 0 ? (
                <p className="text-sm" style={{ color: "#55556a" }}>No invoices yet.</p>
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
                <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                  Payments ({(profile.payments as FinanceRecord[]).length})
                </p>
                <button
                  className="rounded-full px-3 py-1 text-xs font-semibold"
                  style={{ background: "rgba(217,93,57,0.1)", border: "1px solid rgba(217,93,57,0.2)", color: "#d95d39" }}
                  onClick={() => setShowPaymentForm((v) => !v)}
                  type="button"
                >
                  {showPaymentForm ? "Cancel" : "+ Record payment"}
                </button>
              </div>

              {showPaymentForm && (
                <div className="rounded-[1.5rem] p-4 space-y-3" style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}>
                  <FormField label="Amount (EUR)">
                    <input
                      className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                      style={{ background: "#111118", border: "1px solid #1a1a28", color: "#F0EDF8" }}
                      type="number"
                      value={paymentForm.amount_cents}
                      onChange={(e) => setPaymentForm({ ...paymentForm, amount_cents: e.target.value })}
                    />
                  </FormField>
                  <FormField label="Paid on">
                    <input
                      className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                      style={{ background: "#111118", border: "1px solid #1a1a28", color: "#F0EDF8" }}
                      type="date"
                      value={paymentForm.paid_on}
                      onChange={(e) => setPaymentForm({ ...paymentForm, paid_on: e.target.value })}
                    />
                  </FormField>
                  <FormField label="Notes (optional)">
                    <input
                      className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                      style={{ background: "#111118", border: "1px solid #1a1a28", color: "#F0EDF8" }}
                      value={paymentForm.notes}
                      onChange={(e) => setPaymentForm({ ...paymentForm, notes: e.target.value })}
                    />
                  </FormField>
                  <button
                    className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
                    style={{ background: "#F0EDF8", color: "#0A0A0F" }}
                    disabled={!paymentForm.amount_cents || recordPaymentMutation.isPending}
                    onClick={() => recordPaymentMutation.mutate()}
                    type="button"
                  >
                    {recordPaymentMutation.isPending ? "Recording…" : "Record payment"}
                  </button>
                  {recordPaymentMutation.error instanceof Error && (
                    <p className="text-xs" style={{ color: "#e07a5f" }}>{recordPaymentMutation.error.message}</p>
                  )}
                </div>
              )}

              {(profile.payments as FinanceRecord[]).length === 0 ? (
                <p className="text-sm" style={{ color: "#55556a" }}>No payments recorded.</p>
              ) : (
                <div className="space-y-2">
                  {(profile.payments as FinanceRecord[]).map((pay) => (
                    <div key={field(pay, "id")} className="rounded-[1.2rem] px-4 py-3" style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}>
                      <div className="flex items-center justify-between gap-3">
                        <span className="text-sm font-semibold" style={{ color: "#F0EDF8" }}>
                          {money(pay.amount_cents)}
                        </span>
                        <span className="text-xs" style={{ color: "#8888aa" }}>{field(pay, "paid_on")}</span>
                      </div>
                      {field(pay, "notes") && (
                        <p className="text-xs mt-0.5" style={{ color: "#55556a" }}>{field(pay, "notes")}</p>
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
                <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                  Credit ledger ({(profile.credit_ledger_entries as FinanceRecord[]).length})
                </p>
                <span className="text-sm font-semibold" style={{ color: "#4db89c" }}>
                  Balance: {money(profile.credit_balance)}
                </span>
              </div>

              {(profile.credit_ledger_entries as FinanceRecord[]).length === 0 ? (
                <p className="text-sm" style={{ color: "#55556a" }}>No credit entries.</p>
              ) : (
                <div className="space-y-2">
                  {(profile.credit_ledger_entries as FinanceRecord[]).map((entry) => (
                    <div key={field(entry, "id")} className="rounded-[1.2rem] px-4 py-3" style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}>
                      <div className="flex items-center justify-between gap-3">
                        <span className="text-sm font-semibold" style={{ color: "#F0EDF8" }}>
                          {money(entry.amount_cents)}
                        </span>
                        <span className="text-xs font-semibold" style={{ color: statusColor(field(entry, "status")) }}>
                          {field(entry, "status")}
                        </span>
                      </div>
                      {field(entry, "description") && (
                        <p className="text-xs mt-0.5" style={{ color: "#55556a" }}>{field(entry, "description")}</p>
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
    if (!confirm("Void this invoice? This cannot be undone.")) return;
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
      if (!res.ok) throw new Error(`Upload failed: ${res.status}`);
      onUploaded();
    } catch (err) {
      setUploadError(err instanceof Error ? err.message : "Upload failed");
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
      setSaveError(err instanceof Error ? err.message : "Save failed");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div
      className="rounded-[1.2rem] px-4 py-3 space-y-2"
      style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}
    >
      <div className="flex items-center justify-between gap-3">
        <span className="text-sm font-semibold" style={{ color: "#F0EDF8" }}>
          {money(invoice.total_cents)}
        </span>
        <div className="flex items-center gap-2">
          <span
            className="text-xs font-semibold"
            style={{ color: statusColor(status) }}
          >
            {status}
          </span>

          {status === "draft" && (
            <button
              type="button"
              onClick={handleIssue}
              disabled={actioning}
              className="rounded-full px-2 py-0.5 text-xs font-semibold disabled:opacity-50 transition-opacity hover:opacity-80"
              style={{ background: "rgba(77,184,156,0.15)", color: "#4db89c", border: "1px solid rgba(77,184,156,0.3)" }}
            >
              {actioning ? "…" : "Issue"}
            </button>
          )}

          {status !== "void" && status !== "paid" && (
            <button
              type="button"
              onClick={handleVoid}
              disabled={actioning}
              className="rounded-full px-2 py-0.5 text-xs font-semibold disabled:opacity-50 transition-opacity hover:opacity-80"
              style={{ background: "rgba(224,122,95,0.1)", color: "#e07a5f", border: "1px solid rgba(224,122,95,0.25)" }}
            >
              Void
            </button>
          )}

          <button
            type="button"
            onClick={() => {
              setEditing((v) => !v);
              setSaveError(null);
            }}
            className="text-xs hover:opacity-70 transition-opacity"
            style={{ color: "#55556a" }}
          >
            {editing ? "Cancel" : "Edit"}
          </button>
        </div>
      </div>

      {/* Notes prominent display */}
      {!editing && (
        <div className="space-y-0.5">
          {field(invoice, "notes") ? (
            <p className="text-sm font-medium" style={{ color: "#c0c0d8" }}>
              {field(invoice, "notes")}
            </p>
          ) : (
            <p className="text-xs italic" style={{ color: "#3a3a52" }}>No description</p>
          )}
          <p className="text-xs" style={{ color: "#55556a" }}>
            Due: {field(invoice, "due_date") || "—"}
          </p>
        </div>
      )}

      {/* Inline edit */}
      {editing && (
        <div className="space-y-2 pt-1">
          <div className="space-y-1">
            <label className="text-xs font-semibold uppercase tracking-[0.15em]" style={{ color: "#55556a" }}>
              Description
            </label>
            <input
              type="text"
              value={editNotes}
              onChange={(e) => setEditNotes(e.target.value)}
              placeholder="Invoice description…"
              className="w-full rounded-xl px-3 py-1.5 text-sm"
              style={{ background: "#13131f", border: "1px solid #2a2a3a", color: "#F0EDF8" }}
            />
          </div>
          <div className="space-y-1">
            <label className="text-xs font-semibold uppercase tracking-[0.15em]" style={{ color: "#55556a" }}>
              Due date
            </label>
            <input
              type="date"
              value={editDueDate}
              onChange={(e) => setEditDueDate(e.target.value)}
              className="w-full rounded-xl px-3 py-1.5 text-sm"
              style={{ background: "#13131f", border: "1px solid #2a2a3a", color: "#F0EDF8" }}
            />
          </div>
          {saveError && <p className="text-xs" style={{ color: "#e07a5f" }}>{saveError}</p>}
          <button
            type="button"
            onClick={handleSaveEdit}
            disabled={saving}
            className="rounded-full px-3 py-1 text-xs font-semibold disabled:opacity-50 transition-opacity hover:opacity-80"
            style={{ background: "rgba(77,184,156,0.15)", color: "#4db89c", border: "1px solid rgba(77,184,156,0.3)" }}
          >
            {saving ? "Saving…" : "Save"}
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
          style={{ background: "#1a1a28", color: "#c0c0d8", border: "1px solid #2a2a3a" }}
        >
          {uploading ? "Uploading…" : hasFile ? "Replace file" : "Upload file"}
        </button>

        {hasFile && (
          <button
            type="button"
            onClick={handleDownload}
            disabled={downloading}
            className="rounded-full px-2.5 py-1 text-xs font-semibold disabled:opacity-50 transition-opacity hover:opacity-70"
            style={{ background: "rgba(77,184,156,0.1)", color: "#4db89c", border: "1px solid rgba(77,184,156,0.25)" }}
          >
            {downloading ? "…" : "Download"}
          </button>
        )}

        {invoiceParams.file_name && (
          <span className="text-xs truncate max-w-[120px]" style={{ color: "#55556a" }}>
            {invoiceParams.file_name}
          </span>
        )}
      </div>

      {uploadError && (
        <p className="text-xs" style={{ color: "#e07a5f" }}>
          {uploadError}
        </p>
      )}
    </div>
  );
}

function InfoRow({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <div className="flex items-center justify-between gap-4 text-sm">
      <span style={{ color: "#55556a" }}>{label}</span>
      <span className="font-semibold" style={{ color: color ?? "#F0EDF8" }}>{value || "—"}</span>
    </div>
  );
}

function FormField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block space-y-1">
      <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>{label}</span>
      {children}
    </label>
  );
}
