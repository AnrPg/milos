"use client";





import {useUiTranslations} from "@/i18n/ui";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback } from "react";

import { createFinancePackage, fetchFinancePackages, type FinanceRecord } from "@/api/finance";
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
  const i18n = useUiTranslations();
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
  const activePackages = packages.filter((pkg) => pkg.active !== false);
  const inactivePackages = packages.filter((pkg) => pkg.active === false);
  const [form, setForm] = useState(BLANK_FORM);
  const [entitlement, setEntitlement] = useState<EntitlementDraft>(DEFAULT_ENTITLEMENT);

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
  return (
    <div className="space-y-4">
      {/* Header row */}
      <div className="flex items-center justify-between gap-4">
        <p className="text-sm font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>
          {activePackages.length} {i18n("activePackagecafcf18")}{activePackages.length !== 1 ? i18n("sa0f1490") : ""}
        </p>
        <button
          className="rounded-full px-4 py-2 text-sm font-semibold"
          style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)", color: "var(--primary)" }}
          onClick={() => setParam("new", "true")}
          type="button"
        >
          {i18n("newPackage909820b")}
        </button>
      </div>

      {/* Package list */}
      <div className="overflow-hidden rounded-[2rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        {packagesQuery.isLoading ? (
          <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
        ) : activePackages.length === 0 ? (
          <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>{i18n("noActivePackages84ac1e8")}</p>
        ) : (
          <PackageRows packages={activePackages} onOpen={(id) => setParam("package", id)} />
        )}
      </div>

      {inactivePackages.length > 0 ? (
        <details className="overflow-hidden rounded-2xl" style={{ border: "1px solid var(--border)" }}>
          <summary className="cursor-pointer px-5 py-3 text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {i18n("archivedPackages6f2dd9a")} {inactivePackages.length}
          </summary>
          <div style={{ background: "var(--panel)", borderTop: "1px solid var(--border)" }}>
            <PackageRows packages={inactivePackages} onOpen={(id) => setParam("package", id)} />
          </div>
        </details>
      ) : null}

      {/* Side panel: package detail */}
      {openPackageId ? (
        <PackagePanel
          packageId={openPackageId}
          packages={packages}
          onClose={() => setParam("package", null)}
        />
      ) : null}

      {/* Side panel: new package */}
      {showNew ? (
        <SidePanel
          title={i18n("newMembershipPackagef93a8cb")}
          subtitle={i18n("packages0a99901")}
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
                {createMutation.isPending ? i18n("creating94d7d8e") : i18n("createPackagebd56259")}
              </button>
              <button
                className="rounded-full px-5 py-2 text-sm font-semibold"
                style={{ background: "var(--border)", color: "var(--text-soft)" }}
                onClick={() => setParam("new", null)}
                type="button"
              >
                {i18n("cancel77dfd21")}
              </button>
            </div>
          }
        >
          <div className="space-y-4">
            <PanelField label={i18n("packageCode4e5df5f")}>
              <input
                className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={form.code}
                onChange={(e) => setForm({ ...form, code: e.target.value })}
              />
            </PanelField>
            <PanelField label={i18n("name709a232")}>
              <input
                className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                value={form.name}
                onChange={(e) => setForm({ ...form, name: e.target.value })}
              />
            </PanelField>
            <div className="grid gap-4 md:grid-cols-2">
              <PanelField label={i18n("family4efb6cb")}>
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
              <PanelField label={i18n("billingPeriodda59f5a")}>
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
            <PanelField label={i18n("priceEur6e2ef14")}>
              <input
                className="w-full rounded-[0.9rem] px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                type="number"
                value={form.price}
                onChange={(e) => setForm({ ...form, price: e.target.value })}
              />
            </PanelField>
            <PanelField label={i18n("tagsCommaSeparated32bf672")}>
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

function PackageRows({ packages, onOpen }: { packages: FinanceRecord[]; onOpen: (id: string) => void }) {
  const i18n = useUiTranslations();
  return packages.map((pkg, index) => (
    <button
      key={field(pkg, "id")}
      className="flex w-full items-center justify-between gap-4 px-6 py-4 text-left transition-opacity hover:opacity-80"
      style={{ borderBottom: index < packages.length - 1 ? "1px solid var(--border)" : "none" }}
      onClick={() => onOpen(field(pkg, "id"))}
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
        <span className="rounded-full px-3 py-1 text-xs font-semibold" style={{ background: "var(--border)", color: pkg.active === false ? "var(--dim)" : "var(--success)" }}>
          {pkg.active === false ? i18n("inactive09af574") : i18n("activea733b80")}
        </span>
        <span style={{ color: "var(--dim)" }}>→</span>
      </div>
    </button>
  ));
}

function PanelField({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block space-y-1">
      <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{label}</span>
      {children}
    </label>
  );
}
