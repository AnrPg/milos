"use client";

import type { ReactNode } from "react";

import type { Machine, StockStatus } from "@/api/inventory";
import { captionClass, captionStyle, Pill } from "@/components/staff/staff-ui";
import { useUiTranslations } from "@/i18n/ui";

// Small pieces shared by the inventory tabs (ADR-104).

export const rowStyle = { background: "var(--panel-muted)", border: "1px solid var(--border)" } as const;
export const subtleText = { color: "var(--dim)" } as const;

export function Field({ label, children, className }: { label: ReactNode; children: ReactNode; className?: string }) {
  return (
    <label className={`block min-w-0 ${className ?? ""}`}>
      <span className={captionClass} style={captionStyle}>
        {label}
      </span>
      <span className="mt-1 block">{children}</span>
    </label>
  );
}

const MACHINE_TONE: Record<Machine["status"], "success" | "warning" | "danger" | "neutral"> = {
  working: "success",
  needs_attention: "warning",
  out_of_order: "danger",
  retired: "neutral",
};

export function MachineStatusPill({ status }: { status: Machine["status"] }) {
  const i18n = useUiTranslations();
  return <Pill tone={MACHINE_TONE[status]}>{i18n(`invStatus_${status}`)}</Pill>;
}

const STOCK_TONE: Record<StockStatus, "success" | "warning" | "danger"> = {
  ok: "success",
  low: "warning",
  critical: "danger",
  out: "danger",
};

export function StockPill({ status }: { status: StockStatus }) {
  const i18n = useUiTranslations();
  return <Pill tone={STOCK_TONE[status]}>{i18n(`invStock_${status}`)}</Pill>;
}

/** A label/value list that skips empty values. */
export function Details({ items }: { items: Array<[ReactNode, ReactNode]> }) {
  const shown = items.filter(([, value]) => value !== null && value !== undefined && value !== "" && value !== false);
  if (shown.length === 0) return null;
  return (
    <dl className="grid grid-cols-1 gap-x-4 gap-y-2 text-sm sm:grid-cols-2">
      {shown.map(([label, value], index) => (
        <div key={index} className="min-w-0">
          <dt className="text-[11px] font-semibold uppercase tracking-[0.14em]" style={subtleText}>
            {label}
          </dt>
          <dd className="break-words" style={{ color: "var(--text-soft)" }}>
            {value}
          </dd>
        </div>
      ))}
    </dl>
  );
}

export function SectionHeading({ children }: { children: ReactNode }) {
  return (
    <h4 className="text-xs font-semibold uppercase tracking-[0.18em]" style={subtleText}>
      {children}
    </h4>
  );
}
