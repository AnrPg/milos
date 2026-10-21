"use client";

import Link from "next/link";
import type { ReactNode } from "react";

// Shared building blocks of the four member hubs (ADR-137). Hubs use fixed
// slots: a card keeps its place and shows an empty state instead of moving
// (brief §4.2, §8.5).

export function HubPage({ title, actions, children }: { title: ReactNode; actions?: ReactNode; children: ReactNode }) {
  return (
    <main className="mx-auto flex w-full max-w-xl flex-col gap-4 px-4 pb-6 pt-4">
      <header className="flex items-center justify-between gap-3">
        <h1 className="text-3xl font-extrabold tracking-tight" style={{ color: "var(--text)" }}>
          {title}
        </h1>
        {actions}
      </header>
      {children}
    </main>
  );
}

export function HubCard({ eyebrow, children, highlighted }: { eyebrow?: string; children: ReactNode; highlighted?: boolean }) {
  return (
    <section
      className="rounded-3xl p-5"
      style={{
        background: highlighted ? "color-mix(in srgb, var(--primary) 8%, var(--panel))" : "var(--panel)",
        border: `1px solid ${highlighted ? "color-mix(in srgb, var(--primary) 45%, transparent)" : "var(--border)"}`,
      }}
    >
      {eyebrow ? (
        <p className="mb-2 text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
          {eyebrow}
        </p>
      ) : null}
      {children}
    </section>
  );
}

export function HubButton({ href, children, primary }: { href: string; children: ReactNode; primary?: boolean }) {
  return (
    <Link
      href={href}
      className="flex min-h-11 flex-1 items-center justify-center gap-2 rounded-2xl px-4 text-sm font-bold"
      style={{
        background: primary ? "var(--primary)" : "var(--panel-raised)",
        color: primary ? "var(--bg)" : "var(--text)",
        border: primary ? "none" : "1px solid var(--border)",
      }}
    >
      {children}
    </Link>
  );
}

export function HubActionTile({ href, label, icon }: { href: string; label: string; icon: ReactNode }) {
  return (
    <Link
      href={href}
      className="flex min-h-20 flex-col items-center justify-center gap-1.5 rounded-2xl px-2 text-xs font-semibold"
      style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
    >
      <span style={{ color: "var(--primary-strong)" }}>{icon}</span>
      {label}
    </Link>
  );
}

export function HubListRow({
  href,
  onClick,
  label,
  detail,
}: {
  href?: string;
  onClick?: () => void;
  label: string;
  detail?: string;
}) {
  const body = (
    <>
      <span className="flex min-w-0 flex-col">
        <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {label}
        </span>
        {detail ? (
          <span className="truncate text-xs" style={{ color: "var(--dim)" }}>
            {detail}
          </span>
        ) : null}
      </span>
      <span aria-hidden="true" style={{ color: "var(--dim)" }}>
        ›
      </span>
    </>
  );
  const className = "flex min-h-12 w-full items-center justify-between gap-3 px-5 py-3 text-left";
  const style = { borderTop: "1px solid var(--border)" };
  if (href) {
    return (
      <Link href={href} className={className} style={style}>
        {body}
      </Link>
    );
  }
  return (
    <button type="button" onClick={onClick} className={className} style={style}>
      {body}
    </button>
  );
}

export function HubList({ children }: { children: ReactNode }) {
  return (
    <section
      className="overflow-hidden rounded-3xl [&>*:first-child]:border-t-0"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      {children}
    </section>
  );
}

const iconProps = {
  width: 22,
  height: 22,
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.8,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
  "aria-hidden": true,
};

export const HubIcons = {
  calendar: (
    <svg {...iconProps}>
      <rect x="3.5" y="5" width="17" height="15.5" rx="2" />
      <path d="M3.5 10h17M8 3v4M16 3v4" />
    </svg>
  ),
  clock: (
    <svg {...iconProps}>
      <circle cx="12" cy="12" r="8.5" />
      <path d="M12 7.5V12l3 2" />
    </svg>
  ),
  video: (
    <svg {...iconProps}>
      <rect x="3" y="6" width="13" height="12" rx="2" />
      <path d="m16 10.5 5-3v9l-5-3" />
    </svg>
  ),
  chat: (
    <svg {...iconProps}>
      <path d="M4 5h16v11H9l-5 4V5Z" />
    </svg>
  ),
  dumbbell: (
    <svg {...iconProps}>
      <path d="M6.5 6.5v11M17.5 6.5v11M3.5 9v6M20.5 9v6M6.5 12h11" />
    </svg>
  ),
};
