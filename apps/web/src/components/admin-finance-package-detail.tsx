"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

import { useUiTranslations } from "@/i18n/ui";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

/**
 * ADR-096: packages are viewed and edited in the finance package panel. This
 * legacy route forwards old links there instead of authoring v1 contracts.
 */
export function AdminFinancePackageDetail({ packageId }: { packageId: string }) {
  const i18n = useUiTranslations();
  const router = useRouter();
  const organizationSlug = useOrganizationSlug();

  useEffect(() => {
    router.replace(
      adminHref(`/admin/finance?tab=packages&package=${encodeURIComponent(packageId)}`, organizationSlug),
    );
  }, [router, organizationSlug, packageId]);

  return <p className="p-6 text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>;
}
