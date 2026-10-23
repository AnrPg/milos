"use client";

import { useTranslations } from "next-intl";

import { BUSINESS_KINDS, type BusinessKind } from "@/api/business-accounts";

/** ADR-184: gym/box or independent coach, as two choice cards. */
export function BusinessKindPicker({ value, onChange }: { value: BusinessKind; onChange: (kind: BusinessKind) => void }) {
  const t = useTranslations("Business");

  return (
    <div role="radiogroup" aria-label={t("form.kind")} className="grid grid-cols-2 gap-2">
      {BUSINESS_KINDS.map((kind) => {
        const selected = kind === value;
        return (
          <button
            key={kind}
            type="button"
            role="radio"
            aria-checked={selected}
            onClick={() => onChange(kind)}
            className="rounded-2xl px-3 py-3 text-start"
            style={{
              background: selected ? "color-mix(in srgb, var(--primary) 12%, var(--panel))" : "var(--bg)",
              border: `1px solid ${selected ? "var(--primary)" : "var(--border)"}`,
              color: "var(--text)",
            }}
          >
            <span className="block text-sm font-semibold">{t(`kind.${kind}`)}</span>
            <span className="mt-0.5 block text-xs" style={{ color: "var(--text-soft)" }}>{t(`kind.${kind}Hint`)}</span>
          </button>
        );
      })}
    </div>
  );
}
