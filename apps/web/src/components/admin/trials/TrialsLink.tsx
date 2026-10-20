"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

/** The settings entry for «Δοκιμαστικά»; the rules have their own page (board 6 Q3). */
export function TrialsLink() {
  const t = useTranslations("Trials");
  const slug = useOrganizationSlug();
  return (
    <Link
      href={adminHref("/admin/trials/settings", slug)}
      className="flex items-center justify-between gap-3 rounded-2xl px-4 py-3"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      <span className="flex flex-col">
        <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("settingsTitle")}</span>
        <span className="text-sm" style={{ color: "var(--muted)" }}>{t("settingsNavHint")}</span>
      </span>
      <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
    </Link>
  );
}
