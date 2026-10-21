"use client";

import type { ReactNode } from "react";
import { useTranslations } from "next-intl";

import type { AnatomyRole } from "@/lib/anatomy/figure";

/** The figure's role colour, from the same theme tokens the 3D figure reads. */
export const ROLE_COLOR: Record<AnatomyRole, string> = {
  primary: "var(--anatomy-primary)",
  secondary: "var(--anatomy-secondary)",
  stabilizer: "var(--anatomy-stabilizer)",
  felt: "var(--anatomy-felt)",
  "heat-low": "var(--anatomy-heat-low)",
  "heat-medium": "var(--anatomy-heat-medium)",
  "heat-high": "var(--anatomy-heat-high)",
};

export function RoleDot({ role }: { role: AnatomyRole }) {
  return <span aria-hidden="true" className="inline-block h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: ROLE_COLOR[role] }} />;
}

/** «Κύριοι · Βοηθητικοί · Σταθεροποίηση» with the role colours. */
export function RoleLegend({ roles = ["primary", "secondary", "stabilizer"] }: { roles?: AnatomyRole[] }) {
  const t = useTranslations("WodGoals");
  return (
    <ul className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs" style={{ color: "var(--text-soft)" }}>
      {roles.map((role) => (
        <li key={role} className="flex items-center gap-1.5">
          <RoleDot role={role} />
          {t(`legend.${role}`)}
        </li>
      ))}
    </ul>
  );
}

/** A muscle chip in its role colour; the body changes the role (or selects), × removes. */
export function MuscleChip({
  label,
  role,
  onPress,
  onRemove,
  pressLabel,
  removeLabel,
  selected = false,
}: {
  label: string;
  role: AnatomyRole;
  onPress?: () => void;
  onRemove?: () => void;
  pressLabel?: string;
  removeLabel?: string;
  selected?: boolean;
}) {
  return (
    <span
      className="inline-flex min-h-9 items-center overflow-hidden rounded-full text-xs font-semibold"
      style={{
        background: `color-mix(in srgb, ${ROLE_COLOR[role]} 22%, var(--panel-raised, var(--card)))`,
        border: `1px solid ${selected ? "var(--text)" : ROLE_COLOR[role]}`,
        color: "var(--text)",
      }}
    >
      <button type="button" onClick={onPress} aria-label={pressLabel} disabled={!onPress} className="flex min-h-9 items-center gap-1.5 ps-3 pe-2">
        <RoleDot role={role} />
        {label}
      </button>
      {onRemove ? (
        <button type="button" onClick={onRemove} aria-label={removeLabel} className="flex min-h-9 items-center pe-3 ps-1 text-sm leading-none" style={{ color: "var(--text-soft)" }}>
          ×
        </button>
      ) : null}
    </span>
  );
}

/** A toggle chip (qualities, felt muscles). */
export function ToggleChip({
  pressed,
  onToggle,
  children,
  tone = "var(--primary)",
  ariaLabel,
}: {
  pressed: boolean;
  onToggle?: () => void;
  children: ReactNode;
  tone?: string;
  ariaLabel?: string;
}) {
  return (
    <button
      type="button"
      aria-pressed={onToggle ? pressed : undefined}
      aria-label={ariaLabel}
      disabled={!onToggle}
      onClick={onToggle}
      className="inline-flex min-h-9 items-center gap-1 rounded-full px-3 text-xs font-semibold"
      style={{
        background: pressed ? `color-mix(in srgb, ${tone} 20%, var(--panel))` : "var(--panel-raised, var(--card))",
        border: `1px solid ${pressed ? tone : "var(--border)"}`,
        color: pressed ? "var(--text)" : "var(--text-soft)",
      }}
    >
      {pressed && onToggle ? <span aria-hidden="true">✓</span> : null}
      {children}
    </button>
  );
}

/** A segmented control (view switches, role choice). */
export function Segmented<T extends string>({
  value,
  options,
  onChange,
  ariaLabel,
}: {
  value: T | null;
  options: Array<{ value: T; label: string }>;
  onChange: (value: T) => void;
  ariaLabel: string;
}) {
  return (
    <div role="radiogroup" aria-label={ariaLabel} className="flex gap-1 rounded-xl p-1" style={{ background: "var(--bg)" }}>
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          role="radio"
          aria-checked={value === option.value}
          onClick={() => onChange(option.value)}
          className="min-h-9 flex-1 rounded-lg px-3 text-xs font-bold"
          style={{
            background: value === option.value ? "var(--card, var(--panel-raised))" : "transparent",
            color: value === option.value ? "var(--text)" : "var(--muted, var(--text-soft))",
          }}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}
