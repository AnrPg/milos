"use client";

import { useTranslations } from "next-intl";

/** «Ένιωσα: …» under a journal entry (ADR-163): felt muscles, then felt qualities. */
export function FeltLine({ felt }: { felt: { muscles: string[]; qualities: string[] } | null | undefined }) {
  const t = useTranslations("WodGoals.felt");
  const anatomy = useTranslations("Anatomy");
  if (!felt || (felt.muscles.length === 0 && felt.qualities.length === 0)) return null;
  const names = [
    ...felt.muscles.map((id) => anatomy(`muscle.${id}` as never)),
    ...felt.qualities.map((id) => anatomy(`quality.${id}` as never)),
  ];
  return (
    <p className="mt-1 text-sm" style={{ color: "var(--text-soft)" }} data-testid="journal-felt-line">
      {t("entryLine", { list: names.join(", ") })}
    </p>
  );
}
