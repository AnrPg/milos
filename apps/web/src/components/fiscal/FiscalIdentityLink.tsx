"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

/** Settings hub › Finance: the way into «Στοιχεία τιμολόγησης». */
export function FiscalIdentityLink() {
  const t = useTranslations("FiscalIdentity");
  const slug = useOrganizationSlug();
  return (
    <Link
      href={adminHref("/admin/settings/billing", slug)}
      data-testid="fiscal-identity-link"
      className="flex items-center justify-between gap-3 rounded-2xl px-4 py-3"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      <span className="flex flex-col">
        <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("title")}</span>
        <span className="text-sm" style={{ color: "var(--muted)" }}>{t("linkHint")}</span>
      </span>
      <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
    </Link>
  );
}
