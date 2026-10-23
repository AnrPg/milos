"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

/** «Πίσω στο Εγώ»: the way back at the top of every Εγώ sub-page (first used on «Τι κάνεις», ADR-183). */
export function BackToMe() {
  const t = useTranslations("FirstRun");
  return (
    <Link href="/me" className="flex min-h-10 items-center self-start text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
      {t("backToMe")}
    </Link>
  );
}
