"use client";

import { useTranslations } from "next-intl";

import type { FinanceRecord } from "@/api/finance";
import { SPARK_ACTIVE_STYLE } from "@/lib/spark";

import { badgeKey, onlineVisibility } from "./sold-online";

/** The list's «Online» badge (ADR-271): «Online · δεν φαίνεται» in the warning colour when members cannot see it yet. */
export function SoldOnlineBadge({ pkg }: { pkg: FinanceRecord }) {
  const t = useTranslations("SoldOnline");
  const key = pkg.sold_online === true ? badgeKey(onlineVisibility(pkg)) : null;
  if (!key) return null;
  const style =
    key === "badge"
      ? SPARK_ACTIVE_STYLE
      : {
          background: "color-mix(in srgb, var(--warning) 14%, transparent)",
          border: "1px solid color-mix(in srgb, var(--warning) 45%, transparent)",
          color: "var(--text)",
        };
  return (
    <span className="whitespace-nowrap rounded-full px-3 py-1 text-xs font-semibold" style={style} data-testid="sold-online-badge">
      {t(key)}
    </span>
  );
}
