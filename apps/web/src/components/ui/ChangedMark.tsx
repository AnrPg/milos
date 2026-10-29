"use client";

import { useTranslations } from "next-intl";

/** «● Αλλαγμένο» next to a field edited but not saved yet (ADR-274). */
export function ChangedMark() {
  const t = useTranslations("SaveBar");
  return (
    <span className="inline-flex items-center gap-1 text-xs font-semibold normal-case tracking-normal" style={{ color: "var(--warning)" }} data-testid="changed-mark">
      <span aria-hidden>●</span>
      {t("changed")}
    </span>
  );
}
