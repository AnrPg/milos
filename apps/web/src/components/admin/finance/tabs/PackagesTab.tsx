"use client";






import {useUiLocale} from "@/i18n/use-ui-locale";
import {useUiTranslations} from "@/i18n/ui";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useRouter, useSearchParams } from "next/navigation";
import { useCallback } from "react";

import { fetchFinancePackages, type FinanceRecord } from "@/api/finance";
import { useSession } from "@/components/session-provider";
import { PackagePanel } from "@/components/admin/finance/panels/PackagePanel";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";
import { PackageWizard } from "@/components/admin/finance/packages/PackageWizard";
import { useT } from "@/components/admin/finance/packages/package-ui";
import { usePackageAuthoring } from "@/components/admin/finance/packages/use-package-authoring";
import { typeLabelKey, type PackageDraft } from "@/components/admin/finance/packages/package-catalog";

function field(record: FinanceRecord | null | undefined, key: string, fallback = "") {
  const value = record?.[key];
  if (value === null || value === undefined) return fallback;
  return String(value);
}

function money(uiLocale: string, cents: unknown) {
  const amount = typeof cents === "number" ? cents : Number(cents ?? 0);
  return new Intl.NumberFormat(uiLocale, { style: "currency", currency: "EUR" }).format(amount / 100);
}

export function PackagesTab() {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
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
  const { catalog, classTypes, error: catalogError } = usePackageAuthoring(token);
  const [duplicateDraft, setDuplicateDraft] = useState<PackageDraft | null>(null);

  return (
    <div className="space-y-4">
      {/* Header row */}
      <div className="flex items-center justify-between gap-4">
        <p className="text-sm font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>
          {i18n("activePackagesCount02af29c", {count: activePackages.length})}
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
          onDuplicate={(draft) => {
            setDuplicateDraft(draft);
            const params = new URLSearchParams(searchParams.toString());
            params.delete("package");
            params.set("new", "true");
            router.replace(`?${params.toString()}`, { scroll: false });
          }}
        />
      ) : null}

      {/* Side panel: new package wizard (ADR-096) */}
      {showNew ? (
        <SidePanel
          title={i18n("newMembershipPackagef93a8cb")}
          subtitle={i18n("packages0a99901")}
          onClose={() => { setDuplicateDraft(null); setParam("new", null); }}
          width="md:max-w-[680px]"
          bare
        >
          {catalog ? (
            <div className="flex min-h-0 flex-1 flex-col">
              <PackageWizard
                key={duplicateDraft ? "duplicate" : "new"}
                catalog={catalog}
                token={token}
                classTypes={classTypes}
                packages={packages}
                initialDraft={duplicateDraft ?? undefined}
                onClose={() => { setDuplicateDraft(null); setParam("new", null); }}
                onCreated={(created) => {
                  setDuplicateDraft(null);
                  const params = new URLSearchParams(searchParams.toString());
                  params.delete("new");
                  params.set("package", String(created.id));
                  router.replace(`?${params.toString()}`, { scroll: false });
                }}
              />
            </div>
          ) : (
            <p className="px-6 py-6 text-sm" style={{ color: "var(--dim)" }}>{catalogError ? i18n("pkgCatalogUnavailable") : i18n("loading33ce417")}</p>
          )}
        </SidePanel>
      ) : null}
    </div>
  );
}

function PackageRows({ packages, onOpen }: { packages: FinanceRecord[]; onOpen: (id: string) => void }) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const t = useT();
  return packages.map((pkg, index) => (
    <button
      key={field(pkg, "id")}
      className="flex w-full items-center justify-between gap-4 px-6 py-4 text-start transition-opacity hover:opacity-80"
      style={{ borderBottom: index < packages.length - 1 ? "1px solid var(--border)" : "none" }}
      onClick={() => onOpen(field(pkg, "id"))}
      type="button"
    >
      <div>
        <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {field(pkg, "name", field(pkg, "code"))}
        </p>
        <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
          {t(typeLabelKey(field(pkg, "package_type", "membership")))} · {t(`pkgBilling_${field(pkg, "billing_period", "monthly")}`)}
        </p>
      </div>
      <div className="flex items-center gap-4">
        <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {money(uiLocale, pkg.base_price_cents)}
        </span>
        <span className="rounded-full px-3 py-1 text-xs font-semibold" style={{ background: "var(--border)", color: pkg.active === false ? "var(--dim)" : "var(--success)" }}>
          {pkg.active === false ? i18n("inactive09af574") : i18n("activea733b80")}
        </span>
        <span style={{ color: "var(--dim)" }}>→</span>
      </div>
    </button>
  ));
}
