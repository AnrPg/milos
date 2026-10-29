"use client";

import Link from "next/link";
import type { ReactNode } from "react";

/*
 * Small pieces of the «Είσπραξη» screens (mockup pilot-gaps screen 2):
 * theme colours only. The fiscal screens' Card, Pill, Chip and Icon are
 * reused from components/fiscal/fiscal-ui.
 */

const PATHS = {
  nfc: (
    <>
      <path d="M6 8.5a6 6 0 0 1 0 7" />
      <path d="M9.5 6a10 10 0 0 1 0 12" />
      <path d="M13 3.5a14 14 0 0 1 0 17" />
      <path d="M17 7.5a8 8 0 0 1 0 9" />
    </>
  ),
  x: <path d="M6 6l12 12M18 6L6 18" />,
  alert: (
    <>
      <path d="M12 3l9.5 17h-19z" />
      <path d="M12 10v4M12 17.5v.01" />
    </>
  ),
  user: (
    <>
      <circle cx="12" cy="8" r="4" />
      <path d="M4 21c.8-4 4-6 8-6s7.2 2 8 6" />
    </>
  ),
  plus: <path d="M12 5v14M5 12h14" />,
  chevron: <path d="M15 5l-7 7 7 7" />,
} as const;

export type CollectIconName = keyof typeof PATHS;

export function CollectIcon({ name, size = 18 }: { name: CollectIconName; size?: number }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      stroke="currentColor"
      strokeWidth={1.9}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      className={name === "chevron" ? "rtl:rotate-180" : undefined}
    >
      {PATHS[name]}
    </svg>
  );
}

const BIG = "flex min-h-12 w-full items-center justify-center gap-2 rounded-2xl px-4 text-base font-bold disabled:opacity-50";
const PRIMARY = { background: "var(--primary)", color: "var(--primary-contrast)" } as const;
const GHOST = { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" } as const;

/** The one main action of a step. */
export function BigButton({
  children,
  onClick,
  disabled,
  ghost = false,
  testId,
  type = "button",
}: {
  children: ReactNode;
  onClick?: () => void;
  disabled?: boolean;
  ghost?: boolean;
  testId?: string;
  type?: "button" | "submit";
}) {
  return (
    <button type={type} onClick={onClick} disabled={disabled} className={BIG} style={ghost ? GHOST : PRIMARY} data-testid={testId}>
      {children}
    </button>
  );
}

export function BigLink({ href, children, ghost = false, testId }: { href: string; children: ReactNode; ghost?: boolean; testId?: string }) {
  return (
    <Link href={href} className={BIG} style={ghost ? GHOST : PRIMARY} data-testid={testId}>
      {children}
    </Link>
  );
}

/** «‹ Είσπραξη · Ποιος πληρώνει;» */
export function Crumb({ title, current, onBack, backLabel }: { title: string; current: ReactNode; onBack?: () => void; backLabel: string }) {
  return (
    <div className="flex min-w-0 items-center gap-2 text-sm" style={{ color: "var(--muted)" }}>
      {onBack ? (
        <button type="button" onClick={onBack} aria-label={backLabel} className="grid h-8 w-8 shrink-0 place-items-center rounded-full" style={{ color: "var(--primary-strong)" }}>
          <CollectIcon name="chevron" size={18} />
        </button>
      ) : null}
      <span className="truncate">
        {title} · <b style={{ color: "var(--text)" }}>{current}</b>
      </span>
    </div>
  );
}

/** A round status mark on the result screens. */
export function BigMark({ tone, children }: { tone: "ok" | "warn" | "bad" | "accent"; children: ReactNode }) {
  const color = { ok: "var(--success)", warn: "var(--warning)", bad: "var(--danger)", accent: "var(--primary-strong)" }[tone];
  return (
    <span className="mx-auto grid h-14 w-14 place-items-center rounded-full" style={{ color, background: `color-mix(in srgb, ${color} 14%, transparent)` }}>
      {children}
    </span>
  );
}

/** Initials in a round badge. */
export function Avatar({ text, url }: { text: string; url?: string | null }) {
  return url ? (
    // eslint-disable-next-line @next/next/no-img-element -- a member's avatar from storage
    <img src={url} alt="" width={36} height={36} className="h-9 w-9 shrink-0 rounded-full object-cover" />
  ) : (
    <span aria-hidden="true" className="grid h-9 w-9 shrink-0 place-items-center rounded-full text-xs font-bold" style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}>
      {text}
    </span>
  );
}

/** An error shown under its field, inside the form (ADR-195, ADR-214). */
export { FieldError } from "@/components/ui/ErrorNotice";

export const fieldInputClass = "w-full rounded-xl px-3 py-2.5 text-base";

export function fieldInputStyle(invalid: boolean) {
  return {
    background: "var(--panel-muted)",
    border: `1px solid ${invalid ? "var(--danger)" : "var(--border-strong)"}`,
    color: "var(--text)",
  } as const;
}
