"use client";

import type { ReactNode, SVGProps } from "react";

/** A toggle chip (several can be on), for times, goals and disciplines. */
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

/** A small read-only tag on a card; `strong` marks what you share. */
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

export type PartnerIconName = "close" | "check" | "undo" | "filters" | "profile" | "pin" | "people";

/** Line icons of Partners in currentColor (never emoji). */
export function PartnerIcon({ name, size = 22, strokeWidth = 2, ...rest }: { name: PartnerIconName; size?: number; strokeWidth?: number } & SVGProps<SVGSVGElement>) {
  const common = {
    width: size,
    height: size,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    "aria-hidden": true,
    focusable: false,
    ...rest,
  };
  switch (name) {
    case "close":
      return (
        <svg {...common}>
          <path d="M6 6l12 12M18 6 6 18" />
        </svg>
      );
    case "check":
      return (
        <svg {...common}>
          <path d="m5 12.5 4.5 4.5L19 7.5" />
        </svg>
      );
    case "undo":
      return (
        <svg {...common}>
          <path d="M9 14 4 9l5-5" />
          <path d="M4 9h10.5a5.5 5.5 0 0 1 0 11H11" />
        </svg>
      );
    case "filters":
      return (
        <svg {...common}>
          <path d="M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M20 18h0" />
          <circle cx="16" cy="6" r="2" />
          <circle cx="10" cy="12" r="2" />
          <circle cx="18" cy="18" r="2" />
        </svg>
      );
    case "profile":
      return (
        <svg {...common}>
          <circle cx="12" cy="8" r="4" />
          <path d="M4 21a8 8 0 0 1 16 0" />
        </svg>
      );
    case "pin":
      return (
        <svg {...common}>
          <path d="M12 21s-7-6.2-7-11.5A7 7 0 0 1 19 9.5C19 14.8 12 21 12 21Z" />
          <circle cx="12" cy="9.5" r="2.5" />
        </svg>
      );
    case "people":
      return (
        <svg {...common}>
          <circle cx="9" cy="8" r="3.5" />
          <path d="M2.5 20a6.5 6.5 0 0 1 13 0" />
          <path d="M16 4.5a3.5 3.5 0 0 1 0 7M18 13.5a6.5 6.5 0 0 1 3.5 6.5" />
        </svg>
      );
  }
}

/** The verification badge on a card: a check and its words. */
export function PartnerBadgePill({ children }: { children: ReactNode }) {
  return (
    <span
      className="inline-flex items-center gap-1 self-start rounded-full px-2.5 py-1 text-xs font-bold"
      style={{ background: "color-mix(in srgb, var(--success) 16%, transparent)", color: "var(--text)" }}
      data-testid="partner-badge"
    >
      <PartnerIcon name="check" size={14} strokeWidth={2.5} />
      {children}
    </span>
  );
}
