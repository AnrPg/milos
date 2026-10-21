"use client";

import type { ReactNode } from "react";

/** A toggle chip (several can be on), for times, goals and the deck's filters. */
export function PartnerChip({
  pressed,
  onToggle,
  disabled,
  children,
}: {
  pressed: boolean;
  onToggle: () => void;
  disabled?: boolean;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      aria-pressed={pressed}
      disabled={disabled}
      onClick={onToggle}
      className="min-h-10 rounded-full px-3.5 text-sm font-semibold disabled:opacity-40"
      style={{
        background: pressed ? "color-mix(in srgb, var(--primary) 16%, var(--panel))" : "var(--panel-raised)",
        border: `1px solid ${pressed ? "var(--primary)" : "var(--border)"}`,
        color: "var(--text)",
      }}
    >
      {children}
    </button>
  );
}

/** A small read-only tag on a card. */
export function PartnerTag({ children, strong }: { children: ReactNode; strong?: boolean }) {
  return (
    <span
      className="rounded-full px-2.5 py-1 text-xs font-semibold"
      style={{
        background: strong ? "color-mix(in srgb, var(--primary) 16%, transparent)" : "var(--panel-raised)",
        color: strong ? "var(--primary-strong, var(--primary))" : "var(--text-soft)",
      }}
    >
      {children}
    </span>
  );
}
