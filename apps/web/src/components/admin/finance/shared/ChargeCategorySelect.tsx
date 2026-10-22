"use client";

import type { CSSProperties } from "react";

import { CHARGE_CATEGORIES, CHARGE_CATEGORY_LABEL_KEYS } from "@/components/admin/finance/shared/charge-category";
import { useUiTranslations } from "@/i18n/ui";
import { Select } from "@/components/ui/Select";

/** Optional category of a manual charge; matching categories get the member discount (ADR-097). */
export function ChargeCategorySelect({
  value,
  onChange,
  className,
  style,
}: {
  value: string;
  onChange: (value: string) => void;
  className?: string;
  style?: CSSProperties;
}) {
  const i18n = useUiTranslations();
  return (
    <div className="space-y-1">
      <Select
        aria-label={i18n("admChargeCategory")}
        className={className}
        onValueChange={(value) => onChange(value)}
        style={style}
        value={value}
      >
        <option value="">{i18n("admChargeCategoryNone")}</option>
        {CHARGE_CATEGORIES.map((category) => (
          <option key={category} value={category}>{i18n(CHARGE_CATEGORY_LABEL_KEYS[category])}</option>
        ))}
      </Select>
      <p className="text-xs font-normal" style={{ color: "var(--dim)" }}>{i18n("admChargeCategoryHint")}</p>
    </div>
  );
}
