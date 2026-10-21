"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

/** The settings entry for «Δημόσια σελίδα»; the editor has its own page (board 3). */
export function PublicPageLink() {
  const t = useTranslations("AdminPublicPage");
  const slug = useOrganizationSlug();
  return (
    <Link
      href={adminHref("/admin/public-page", slug)}
      className="flex items-center justify-between gap-3 rounded-2xl px-4 py-3"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      <span className="flex flex-col">
        <span className="text-sm font-bold" style={{ color: "var(--text)" }}>
          {t("navLabel")}
        </span>
        <span className="text-sm" style={{ color: "var(--muted)" }}>
          {t("navHint")}
        </span>
      </span>
      <span aria-hidden="true" style={{ color: "var(--dim)" }}>
        ›
      </span>
    </Link>
  );
}
