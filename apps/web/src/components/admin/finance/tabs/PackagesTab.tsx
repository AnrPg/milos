"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback } from "react";

import { backfillFinanceEntitlements, createFinancePackage, fetchFinancePackages, type EntitlementBackfillReport, type FinanceRecord } from "@/api/finance";
import { useSession } from "@/components/session-provider";
import { PackagePanel } from "@/components/admin/finance/panels/PackagePanel";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";
import {
  DEFAULT_ENTITLEMENT,
  EntitlementEditor,
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

const BLANK_FORM = { code: "", name: "", family: "unlimited", billing_period: "monthly", price: "", tags: "" };

export function PackagesTab() {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const router = useRouter();
  const searchParams = useSearchParams();

  const openPackageId = searchParams.get("package");
  const showNew = searchParams.get("new") === "true";

  const setParam = useCallback(
    (key: string, value: string | null) => {
      const params = new URLSearchParams(searchParams.toString());
      if (value === null) params.delete(key);
      else params.set(key, value);
      router.replace(`?${params.toString()}`, { scroll: false });
    },
    [router, searchParams],
  );

  const packagesQuery = useQuery({
    queryKey: ["admin", "finance", "packages"],
    enabled: Boolean(token),
    queryFn: () => fetchFinancePackages(token),
  });

  const packages = packagesQuery.data?.packages ?? [];
  const [form, setForm] = useState(BLANK_FORM);
  const [entitlement, setEntitlement] = useState<EntitlementDraft>(DEFAULT_ENTITLEMENT);
  const [legacyPackages, setLegacyPackages] = useState({ member: "", athlete: "" });
  const [backfillReport, setBackfillReport] = useState<EntitlementBackfillReport | null>(null);

  const createMutation = useMutation({
    mutationFn: () =>
      createFinancePackage(token, {
        code: form.code,
        name: form.name,
        family: form.family,
        billing_period: form.billing_period,
        base_price_cents: Math.round(Number(form.price || 0) * 100),
        currency: "EUR",
        tags: form.tags.split(",").map((t) => t.trim()).filter(Boolean),
        params: entitlementParams(entitlement),
      }),
    onSuccess: async () => {
      setForm(BLANK_FORM);
      setEntitlement(DEFAULT_ENTITLEMENT);
      setParam("new", null);
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "packages"] });
    },
  });
  const backfillMutation = useMutation({
    mutationFn: (dryRun: boolean) => backfillFinanceEntitlements(token, {
      dry_run: dryRun,
      package_by_role: Object.fromEntries(Object.entries(legacyPackages).filter(([, value]) => value)),
    }),
    onSuccess: setBackfillReport,
  });

  return (
    <div className="space-y-4">
      {/* Header row */}
      <div className="flex items-center justify-between gap-4">
        <p className="text-sm font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>
          {packages.length} package{packages.length !== 1 ? "s" : ""}
        </p>
        <button
          className="rounded-full px-4 py-2 text-sm font-semibold"
          style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)", color: "var(--primary)" }}
          onClick={() => setParam("new", "true")}
          type="button"
        >
          + New package
        </button>
      </div>

      <section className="rounded-[2rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div><h3 className="text-sm font-semibold" style={{ color: "var(--text)" }}>Legacy entitlement rollout</h3><p className="mt-1 max-w-2xl text-xs leading-5" style={{ color: "var(--dim)" }}>Map legacy members and athletes to approved versioned packages. Dry-run classifies every account; apply creates only missing profiles/subscriptions and is safe to repeat.</p></div>
          <div className="flex gap-2"><button type="button" disabled={backfillMutation.isPending} onClick={() => backfillMutation.mutate(true)} className="rounded-full px-3 py-2 text-xs font-semibold" style={{ background: "var(--border)" }}>Check readiness</button><button type="button" disabled={backfillMutation.isPending || (!legacyPackages.member && !legacyPackages.athlete)} onClick={() => backfillMutation.mutate(false)} className="rounded-full px-3 py-2 text-xs font-semibold disabled:opacity-50" style={{ background: "var(--primary)", color: "var(--bg)" }}>Apply backfill</button></div>
        </div>
        <div className="mt-4 grid gap-3 sm:grid-cols-2">{(["member", "athlete"] as const).map((role) => <label key={role} className="space-y-1"><span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>Legacy {role} package</span><select className="w-full rounded-xl px-3 py-2 text-sm" style={{ background: "var(--bg-soft)", border: "1px solid var(--border)" }} value={legacyPackages[role]} onChange={(event) => setLegacyPackages({ ...legacyPackages, [role]: event.target.value })}><option value="">Not mapped</option>{packages.filter((pkg) => pkg.active !== false).map((pkg) => <option key={field(pkg, "id")} value={field(pkg, "id")}>{field(pkg, "name", field(pkg, "code"))}</option>)}</select></label>)}</div>
        {backfillReport ? <p className="mt-3 text-xs" style={{ color: backfillReport.ready ? "var(--success)" : "var(--warning)" }}>{backfillReport.ready ? "Ready for strict enforcement." : "Backfill still required."} {Object.entries(backfillReport.counts).map(([key, value]) => `${key.replaceAll("_", " ")}: ${value}`).join(" · ")}</p> : null}
        {backfillMutation.isError ? <p className="mt-3 text-xs" style={{ color: "var(--danger)" }}>Readiness/backfill failed. Confirm both selected packages contain valid entitlement contracts.</p> : null}
      </section>

      {/* Package list */}
      <div className="rounded-[2rem] overflow-hidden" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        {packagesQuery.isLoading ? (
          <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>Loading…</p>
        ) : packages.length === 0 ? (
          <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>No packages yet.</p>
        ) : (
          packages.map((pkg, i) => (
            <button
              key={field(pkg, "id")}
              className="flex w-full items-center justify-between gap-4 px-6 py-4 text-left transition-opacity hover:opacity-80"
              style={{ borderBottom: i < packages.length - 1 ? "1px solid var(--border)" : "none" }}
              onClick={() => setParam("package", field(pkg, "id"))}
              type="button"
            >
              <div>
                <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                  {field(pkg, "name", field(pkg, "code"))}
                </p>
                <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
                  {field(pkg, "code")} · {field(pkg, "family")} · {field(pkg, "billing_period")}
                </p>
              </div>
              <div className="flex items-center gap-4">
                <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                  {money(pkg.base_price_cents)}
                </span>
                <span
                  className="rounded-full px-3 py-1 text-xs font-semibold"
                  style={
                    pkg.active !== false
                      ? { background: "color-mix(in srgb, var(--success) 12%, transparent)", color: "var(--success)" }
                      : { background: "var(--border)", color: "var(--dim)" }
                  }
                >
                  {pkg.active !== false ? "Active" : "Inactive"}
                </span>
                <span style={{ color: "var(--dim)" }}>→</span>
              </div>
            </button>
          ))
        )}
      </div>

      {/* Side panel: package detail */}
      {openPackageId ? (
        <PackagePanel
          packageId={openPackageId}
          onClose={() => setParam("package", null)}
        />
      ) : null}

      {/* Side panel: new package */}
      {showNew ? (
        <SidePanel
          title="New membership package"
          subtitle="Packages"
          onClose={() => setParam("new", null)}
          footer={
            <div className="flex gap-3">
              <button
                className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50"
                style={{ background: "var(--text)", color: "var(--bg)" }}
                disabled={createMutation.isPending || !form.code || !form.name}
                onClick={() => createMutation.mutate()}
                type="button"
              >
                {createMutation.isPending ? "Creating…" : "Create package"}
              </button>
              <button
                className="rounded-full px-5 py-2 text-sm font-semibold"
                style={{ background: "var(--border)", color: "var(--text-soft)" }}
                onClick={() => setParam("new", null)}
                type="button"
              >
                Cancel
              </button>
            </div>
          }
        >
          <div className="space-y-4">
            <PanelField label="Package code">
              <input
                className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={form.code}
                onChange={(e) => setForm({ ...form, code: e.target.value })}
              />
            </PanelField>
            <PanelField label="Name">
              <input
                className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={form.name}
                onChange={(e) => setForm({ ...form, name: e.target.value })}
              />
            </PanelField>
            <div className="grid gap-4 md:grid-cols-2">
              <PanelField label="Family">
                <select
                  className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                  value={form.family}
                  onChange={(e) => setForm({ ...form, family: e.target.value })}
                >
                  {["unlimited", "limited-visits", "personal-programming", "hybrid"].map((v) => (
                    <option key={v} value={v}>{v}</option>
                  ))}
                </select>
              </PanelField>
              <PanelField label="Billing period">
                <select
                  className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                  value={form.billing_period}
                  onChange={(e) => setForm({ ...form, billing_period: e.target.value })}
                >
                  {["monthly", "quarterly", "annual", "custom"].map((v) => (
                    <option key={v} value={v}>{v}</option>
                  ))}
                </select>
              </PanelField>
            </div>
            <PanelField label="Price (EUR)">
              <input
                className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                type="number"
                value={form.price}
                onChange={(e) => setForm({ ...form, price: e.target.value })}
              />
            </PanelField>
            <PanelField label="Tags (comma-separated)">
              <input
                className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={form.tags}
                onChange={(e) => setForm({ ...form, tags: e.target.value })}
              />
            </PanelField>
            <EntitlementEditor value={entitlement} onChange={setEntitlement} />
            {createMutation.error instanceof Error && (
              <p className="text-sm" style={{ color: "var(--primary-strong)" }}>{createMutation.error.message}</p>
            )}
          </div>
        </SidePanel>
      ) : null}
    </div>
  );
}

function PanelField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block space-y-1">
      <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{label}</span>
      {children}
    </label>
  );
}
