"use client";

import type { ReactNode } from "react";

import { Pill } from "@/components/staff/staff-ui";

export { Pill };

/** One setting row of a panel's settings card (mockup `setrow`): label and hint on the start, the control on the end. */
export function SettingRow({ label, hint, children }: { label: string; hint?: ReactNode; children: ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3 py-2">
      <div className="flex min-w-0 flex-col">
        <b className="text-sm" style={{ color: "var(--text)" }}>
          {label}
        </b>
        {hint ? (
          <span className="text-xs leading-5" style={{ color: "var(--dim)" }}>
            {hint}
          </span>
        ) : null}
      </div>
      {children}
    </div>
  );
}

export function Card({ children, className = "" }: { children: ReactNode; className?: string }) {
  return (
    <div className={`rounded-2xl px-4 py-2 ${className}`} style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      {children}
    </div>
  );
}

export function Hint({ children }: { children: ReactNode }) {
  return (
    <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>
      {children}
    </p>
  );
}

/** A short warning inside a panel or form, on the warning tint. */
export function Notice({ icon, testId, children }: { icon: string; testId?: string; children: ReactNode }) {
  return (
    <p
      role="note"
      data-testid={testId}
      className="rounded-xl px-3 py-2 text-xs font-semibold leading-5"
      style={{
        background: "color-mix(in srgb, var(--warning) 12%, transparent)",
        border: "1px solid color-mix(in srgb, var(--warning) 35%, transparent)",
        color: "var(--text)",
      }}
    >
      <span aria-hidden="true">{icon} </span>
      {children}
    </p>
  );
}

/** The short warning staff see before a mandatory publish blocks booking (product owner question pending). */
export function BookingBlockWarning({ children }: { children: ReactNode }) {
  return (
    <Notice icon="🔒" testId="booking-block-warning">
      {children}
    </Notice>
  );
}

export function Toast({ children }: { children: ReactNode }) {
  return (
    <p role="status" className="rounded-xl px-3 py-2 text-sm font-semibold" style={{ background: "color-mix(in srgb, var(--success) 12%, transparent)", color: "var(--success)" }}>
      ✓ {children}
    </p>
  );
}

export function PersonRow({ name, detail, action }: { name: string; detail?: ReactNode; action?: ReactNode }) {
  return (
    <li className="flex items-center justify-between gap-3 py-2.5" style={{ borderTop: "1px solid var(--border)" }}>
      <span className="flex min-w-0 flex-col">
        <span className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
          {name}
        </span>
        {detail ? (
          <span className="text-xs" style={{ color: "var(--dim)" }}>
            {detail}
          </span>
        ) : null}
      </span>
      {action}
    </li>
  );
}

export const linkButtonClass = "text-sm font-semibold disabled:opacity-50";
