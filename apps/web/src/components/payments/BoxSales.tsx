"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { fetchPublicPackages, publicPackagesKey } from "@/api/my-payments";
import { nativePlatform } from "@/lib/platform";
import { FRESHNESS } from "@/lib/query-policy";

import { BuyPackageSheet } from "./BuyPackageSheet";
import { buyableHere, renewalPackages } from "./checkout-flow";

/**
 * What a box sells online that may be bought on this device (ADR-248,
 * ADR-256): nothing when the box takes no online payments, and never a
 * digital-only package inside the store apps.
 */
export function useBoxSales(slug: string | null | undefined) {
  const query = useQuery({
    queryKey: publicPackagesKey(slug ?? "none"),
    enabled: Boolean(slug),
    queryFn: () => fetchPublicPackages(slug!),
    staleTime: FRESHNESS.reference,
    retry: false,
  });
  const data = query.data;
  const packages = data?.online_payments ? buyableHere(data.packages, nativePlatform()) : [];
  return { packages, provider: data?.provider ?? null, isLoading: query.isLoading };
}

/** Box › «Συνδρομή» › «Ανανέωση» (mockup s4 option B, sheet 1). */
export function RenewButton({ slug }: { slug: string }) {
  const t = useTranslations("Pay");
  const { packages } = useBoxSales(slug);
  const [open, setOpen] = useState(false);
  if (renewalPackages(packages).length === 0) return null;

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="flex min-h-11 flex-1 items-center justify-center gap-2 rounded-2xl px-4 text-sm font-bold"
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        data-testid="pay-renew"
      >
        {t("renew")}
      </button>
      {open ? (
        <BuyPackageSheet slug={slug} packages={packages} mode={{ kind: "renew" }} origin="box" onClose={() => setOpen(false)} />
      ) : null}
    </>
  );
}
