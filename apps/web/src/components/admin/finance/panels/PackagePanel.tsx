"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { fetchFinancePackage, updateFinancePackage, type FinanceRecord } from "@/api/finance";
import { useSession } from "@/components/session-provider";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";
import {
  EntitlementEditor,
  entitlementDraft,
  entitlementParams,
  type EntitlementDraft,
} from "@/components/admin/finance/shared/EntitlementEditor";

function field(record: FinanceRecord | null | undefined, key: string, fallback = "") {
  const value = record?.[key];
  if (value === null || value === undefined) return fallback;
  return String(value);
}

function money(cents: unknown) {
  const amount = typeof cents === "number" ? cents : Number(cents ?? 0);
  return new Intl.NumberFormat("en-GB", { style: "currency", currency: "EUR" }).format(amount / 100);
}

export function PackagePanel({ packageId, onClose }: { packageId: string; onClose: () => void }) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();

  const packageQuery = useQuery({
    queryKey: ["admin", "finance", "package", packageId],
    enabled: Boolean(token),
    queryFn: () => fetchFinancePackage(token, packageId),
  });

  const pkg = packageQuery.data?.package ?? null;

  const [form, setForm] = useState<FinanceRecord | null>(null);
  const [entitlement, setEntitlement] = useState<EntitlementDraft | null>(null);
  const editing = form !== null;

  function startEdit() {
    if (!pkg) return;
    setForm({
      name: field(pkg, "name"),
      description: field(pkg, "description"),
      family: field(pkg, "family"),
      billing_period: field(pkg, "billing_period"),
      base_price_cents: pkg.base_price_cents ?? 0,
      tags: Array.isArray(pkg.tags) ? (pkg.tags as string[]).join(", ") : "",
      active: pkg.active !== false,
    });
    setEntitlement(entitlementDraft(pkg.params));
  }

  const updateMutation = useMutation({
    mutationFn: () => {
      if (!form) throw new Error("No form");
      const tags = typeof form.tags === "string"
        ? (form.tags as string).split(",").map((t) => t.trim()).filter(Boolean)
        : [];
      if (!entitlement) throw new Error("No entitlement contract");
      return updateFinancePackage(token, packageId, {
        ...form,
        tags,
        params: entitlementParams(entitlement),
      });
    },
    onSuccess: async () => {
      setForm(null);
      setEntitlement(null);
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "package", packageId] });
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "packages"] });
    },
  });

  return (
    <SidePanel
      title={pkg ? field(pkg, "name", field(pkg, "code")) : "Package"}
      subtitle="Membership Package"
      onClose={onClose}
      footer={
        editing ? (
          <div className="flex gap-3">
            <button
              className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--text)", color: "var(--bg)" }}
              disabled={updateMutation.isPending}
              onClick={() => updateMutation.mutate()}
              type="button"
            >
              {updateMutation.isPending ? "Saving…" : "Save changes"}
            </button>
            <button
              className="rounded-full px-5 py-2 text-sm font-semibold"
              style={{ background: "var(--border)", color: "var(--text-soft)" }}
              onClick={() => { setForm(null); setEntitlement(null); }}
              type="button"
            >
              Cancel
            </button>
          </div>
        ) : (
          <button
            className="rounded-full px-5 py-2 text-sm font-semibold"
            style={{ background: "var(--border)", color: "var(--text-soft)" }}
            onClick={startEdit}
            type="button"
          >
            Edit package
          </button>
        )
      }
    >
      {packageQuery.isLoading ? (
        <p style={{ color: "var(--dim)" }}>Loading…</p>
      ) : !pkg ? (
        <p style={{ color: "var(--primary-strong)" }}>Package not found.</p>
      ) : editing && form ? (
        <div className="space-y-4">
          <Field label="Name">
            <input
              className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
              value={String(form.name ?? "")}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
            />
          </Field>
          <Field label="Description">
            <input
              className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
              value={String(form.description ?? "")}
              onChange={(e) => setForm({ ...form, description: e.target.value })}
            />
          </Field>
          <div className="grid gap-4 md:grid-cols-2">
            <Field label="Family">
              <select
                className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={String(form.family ?? "")}
                onChange={(e) => setForm({ ...form, family: e.target.value })}
              >
                {["unlimited", "limited-visits", "personal-programming", "hybrid"].map((v) => (
                  <option key={v} value={v}>{v}</option>
                ))}
              </select>
            </Field>
            <Field label="Billing period">
              <select
                className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={String(form.billing_period ?? "")}
                onChange={(e) => setForm({ ...form, billing_period: e.target.value })}
              >
                {["monthly", "quarterly", "annual", "custom"].map((v) => (
                  <option key={v} value={v}>{v}</option>
                ))}
              </select>
            </Field>
          </div>
          <Field label="Base price (EUR)">
            <input
              className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
              type="number"
              value={Number(form.base_price_cents ?? 0) / 100}
              onChange={(e) => setForm({ ...form, base_price_cents: Math.round(Number(e.target.value) * 100) })}
            />
          </Field>
          <Field label="Tags (comma-separated)">
            <input
              className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
              value={String(form.tags ?? "")}
              onChange={(e) => setForm({ ...form, tags: e.target.value })}
            />
          </Field>
          {entitlement ? <EntitlementEditor value={entitlement} onChange={setEntitlement} /> : null}
          <label className="flex items-center gap-3 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            <input
              type="checkbox"
              checked={form.active !== false}
              onChange={(e) => setForm({ ...form, active: e.target.checked })}
            />
            Active
          </label>
          {updateMutation.error instanceof Error && (
            <p className="text-sm" style={{ color: "var(--primary-strong)" }}>{updateMutation.error.message}</p>
          )}
        </div>
      ) : (
        <div className="space-y-4">
          <Stat label="Code" value={field(pkg, "code")} />
          <Stat label="Name" value={field(pkg, "name")} />
          <Stat label="Family" value={field(pkg, "family")} />
          <Stat label="Billing period" value={field(pkg, "billing_period")} />
          <Stat label="Base price" value={money(pkg.base_price_cents)} />
          <Stat label="Status" value={pkg.active !== false ? "Active" : "Inactive"} />
          <EntitlementSummary params={pkg.params} />
          {Array.isArray(pkg.tags) && (pkg.tags as string[]).length > 0 && (
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.18em] mb-2" style={{ color: "var(--dim)" }}>Tags</p>
              <div className="flex flex-wrap gap-2">
                {(pkg.tags as string[]).map((tag) => (
                  <span key={tag} className="rounded-full px-3 py-1 text-xs font-semibold" style={{ background: "var(--border)", color: "var(--text-soft)" }}>{tag}</span>
                ))}
              </div>
            </div>
          )}
        </div>
      )}
    </SidePanel>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block space-y-1">
      <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{label}</span>
      {children}
    </label>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{label}</p>
      <p className="mt-1 text-sm font-semibold" style={{ color: "var(--text)" }}>{value || "—"}</p>
    </div>
  );
}

function EntitlementSummary({ params }: { params: unknown }) {
  const draft = entitlementDraft(params);
  return (
    <div className="space-y-2 rounded-xl p-4" style={{ background: "var(--bg-soft)" }}>
      <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>Entitlements</p>
      <p className="text-sm"><strong>Channels:</strong> {draft.channels.join(", ") || "None"}</p>
      <p className="text-sm"><strong>Capabilities:</strong> {draft.capabilities.join(", ") || "None"}</p>
      <p className="text-sm"><strong>Class visits:</strong> {draft.classVisitLimit} / {draft.classVisitPeriod.replaceAll("_", " ")}</p>
      <p className="text-sm"><strong>Coaching:</strong> {draft.coachingTouchpointLimit} / {draft.coachingTouchpointPeriod.replaceAll("_", " ")}</p>
    </div>
  );
}
