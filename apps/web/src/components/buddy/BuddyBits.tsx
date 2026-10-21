"use client";

import Link from "next/link";
import type { ReactNode } from "react";

/** A small count badge (unread messages, new requests). */
export function CountBadge({ count, label }: { count: number; label: string }) {
  if (count <= 0) return null;
  return (
    <span
      aria-label={label}
      className="inline-flex min-w-6 items-center justify-center rounded-full px-1.5 py-0.5 text-xs font-bold tabular-nums"
      style={{ background: "var(--primary)", color: "var(--bg)" }}
      data-testid="buddy-unread"
    >
      {count > 99 ? "99+" : count}
    </span>
  );
}

/** A labelled switch (checkbox semantics as a switch). */
export function SwitchRow({
  checked,
  onChange,
  label,
  hint,
  disabled,
}: {
  checked: boolean;
  onChange: (next: boolean) => void;
  label: string;
  hint?: string;
  disabled?: boolean;
}) {
  return (
    <label className="flex min-h-11 items-center justify-between gap-3">
      <span className="flex min-w-0 flex-col">
        <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{label}</span>
        {hint ? <span className="text-xs" style={{ color: "var(--dim)" }}>{hint}</span> : null}
      </span>
      <input
        type="checkbox"
        role="switch"
        checked={checked}
        disabled={disabled}
        onChange={(event) => onChange(event.target.checked)}
        className="h-5 w-5 shrink-0"
        style={{ accentColor: "var(--primary)" }}
      />
    </label>
  );
}

export function BackLink({ href, children }: { href: string; children: ReactNode }) {
  return (
    <Link href={href} className="inline-flex min-h-11 items-center text-sm font-semibold" style={{ color: "var(--primary)" }}>
      ← {children}
    </Link>
  );
}

export function Muted({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <p className={["text-sm", className].join(" ")} style={{ color: "var(--muted)" }}>
      {children}
    </p>
  );
}

export function HeartIcon({ size = 18 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10Z" />
    </svg>
  );
}
