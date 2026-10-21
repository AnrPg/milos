"use client";

import { useTranslations } from "next-intl";

/** «Σεζόν · Hyrox prep» under a workout that belongs to a season (ADR-167). */
export function SeasonTag({ season }: { season?: { title?: string | null } | null }) {
  const t = useTranslations("Seasons");
  const title = season?.title?.trim();
  if (!title) return null;
  return (
    <p className="mt-0.5 truncate text-[11px] font-semibold" style={{ color: "var(--primary-strong)" }}>
      {t("tag", { title })}
    </p>
  );
}
