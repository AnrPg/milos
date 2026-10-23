"use client";

import Link from "next/link";
import type { ReactNode } from "react";

// Building blocks of the staff dashboard (ADR-135): one card style, a class
// timeline, avatar chips, action tiles, status dots and icon tiles. Every
// state carries text as well as color, and each card shows one idea.

export type IconName =
  | "users"
  | "wallet"
  | "calendar"
  | "check"
  | "dumbbell"
  | "coach"
  | "clock"
  | "sparkle"
  | "box"
  | "play"
  | "chart"
  | "trophy"
  | "star"
  | "heart"
  | "leaf"
  | "plus"
  | "card"
  | "file"
  | "bag";

const ICON_PATHS: Record<IconName, ReactNode> = {
  users: (
    <>
      <circle cx="9" cy="8" r="3.5" />
      <path d="M2.5 20c.6-3.6 3.2-5.5 6.5-5.5s5.9 1.9 6.5 5.5" />
      <path d="M16 4.8a3.3 3.3 0 0 1 0 6.4M18.5 14.8c1.6.7 2.7 2.4 3 5.2" />
    </>
  ),
  wallet: (
    <>
      <rect x="3" y="6" width="18" height="13" rx="3" />
      <path d="M3 10h18M16 14.5h2" />
    </>
  ),
  calendar: (
    <>
      <rect x="3.5" y="5" width="17" height="15" rx="3" />
      <path d="M3.5 10h17M8 3v4M16 3v4" />
    </>
  ),
  check: (
    <>
      <circle cx="12" cy="12" r="8.5" />
      <path d="m8 12.3 2.6 2.6L16.2 9" />
    </>
  ),
  dumbbell: <path d="M6.5 7v10M17.5 7v10M3.5 9.5v5M20.5 9.5v5M6.5 12h11" />,
  coach: (
    <>
      <circle cx="12" cy="7.5" r="3.5" />
      <path d="M5 20c.8-4 3.4-6 7-6s6.2 2 7 6M12 14v3" />
    </>
  ),
  clock: (
    <>
      <circle cx="12" cy="12" r="8.5" />
      <path d="M12 7.5V12l3 2" />
    </>
  ),
  sparkle: <path d="M12 3.5 13.8 10l6.7 2-6.7 2L12 20.5 10.2 14l-6.7-2 6.7-2zM19 3.5v3M17.5 5h3" />,
  box: (
    <>
      <path d="m12 3 8 4.5v9L12 21l-8-4.5v-9z" />
      <path d="m4 7.5 8 4.5 8-4.5M12 12v9" />
    </>
  ),
  play: (
    <>
      <rect x="3" y="5" width="18" height="14" rx="3" />
      <path d="m10.5 9.5 4 2.5-4 2.5z" />
    </>
  ),
  chart: <path d="M4 20V4M4 20h16M8 16v-5M12 16V8M16 16v-3" />,
  trophy: (
    <>
      <path d="M8 4h8v5a4 4 0 0 1-8 0zM8 6H5a3 3 0 0 0 3 4M16 6h3a3 3 0 0 1-3 4" />
      <path d="M12 13v4M9 20h6" />
    </>
  ),
  star: <path d="m12 4 2.4 5 5.4.6-4 3.7 1.1 5.3L12 16l-4.9 2.6 1.1-5.3-4-3.7 5.4-.6z" />,
  heart: <path d="M12 19.5s-7.5-4.4-7.5-9.7A4.1 4.1 0 0 1 12 7.6a4.1 4.1 0 0 1 7.5 2.2c0 5.3-7.5 9.7-7.5 9.7z" />,
  leaf: (
    <>
      <path d="M5 19c0-8 5-13 14-14 0 9-5 14-13 14z" />
      <path d="M5 19c3-4 6-6.5 9.5-8.5" />
    </>
  ),
  plus: (
    <>
      <circle cx="12" cy="12" r="8.5" />
      <path d="M12 8v8M8 12h8" />
    </>
  ),
  card: (
    <>
      <rect x="3" y="6" width="18" height="12" rx="2.5" />
      <path d="M3 10h18M7 14.5h3" />
    </>
  ),
  file: (
    <>
      <path d="M7 3.5h7l4 4v13H7z" />
      <path d="M14 3.5v4h4M10 12h5M10 15.5h5" />
    </>
  ),
  bag: (
    <>
      <path d="M5 8h14l-1 13H6z" />
      <path d="M9 8V6a3 3 0 0 1 6 0v2" />
    </>
  ),
};

export function DashboardIcon({ name, className = "h-5 w-5" }: { name: IconName; className?: string }) {
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.7}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
    >
      {ICON_PATHS[name]}
    </svg>
  );
}

/** The one card style of the dashboard: eyebrow, optional title, badge and action. */
export function DashboardCard({
  id,
  eyebrow,
  title,
  badge,
  action,
  className = "",
  children,
}: {
  id?: string;
  eyebrow: string;
  title?: ReactNode;
  badge?: ReactNode;
  action?: ReactNode;
  className?: string;
  children?: ReactNode;
}) {
  return (
    <section
      id={id}
      aria-label={eyebrow}
      className={`flex min-w-0 flex-col rounded-[2.2rem] p-6 ${className}`}
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <p className="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>
            <span className="truncate">{eyebrow}</span>
            {badge}
          </p>
          {title ? (
            <h2 className="mt-2 text-xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>
              {title}
            </h2>
          ) : null}
        </div>
        {action ? <div className="shrink-0">{action}</div> : null}
      </div>
      {children ? <div className="mt-5 min-w-0 flex-1">{children}</div> : null}
    </section>
  );
}

export function CountBadge({ value, tone = "neutral" }: { value: number; tone?: "neutral" | "primary" }) {
  return (
    <span
      className="rounded-full px-2 py-0.5 text-[10px] font-bold tracking-normal"
      style={{
        background: tone === "primary" ? "color-mix(in srgb, var(--primary) 16%, transparent)" : "var(--border)",
        color: tone === "primary" ? "var(--primary-strong)" : "var(--text-soft)",
      }}
    >
      {value}
    </span>
  );
}

/** A small link in a card header ("Open →"). */
export function CardLink({ href, children }: { href: string; children: ReactNode }) {
  return (
    <Link
      href={href}
      className="rounded-full px-4 py-2 text-sm font-semibold transition-opacity hover:opacity-80"
      style={{ background: "var(--border)", border: "1px solid var(--border-strong)", color: "var(--text-soft)" }}
    >
      {children}
    </Link>
  );
}

/** A calm empty state that points at the next step. */
export function EmptyNote({ children, action }: { children: ReactNode; action?: ReactNode }) {
  return (
    <div
      className="flex flex-wrap items-center justify-between gap-3 rounded-2xl px-4 py-5 text-sm"
      style={{ background: "var(--panel-muted)", color: "var(--dim)" }}
    >
      <span>{children}</span>
      {action}
    </div>
  );
}

export type TimelineEntry = {
  id: string;
  time: string;
  title: string;
  href: string;
  /** e.g. "8 booked of 12" — always shown next to the bar. */
  caption: string;
  filled: number;
  capacity: number;
  past?: boolean;
};

/** Today's classes as a vertical timeline with a capacity bar per class. */
export function ClassTimeline({ entries }: { entries: TimelineEntry[] }) {
  return (
    <ol className="relative space-y-3">
      {entries.map((entry, index) => {
        const ratio = entry.capacity > 0 ? Math.min(1, entry.filled / entry.capacity) : 0;
        const full = entry.capacity > 0 && entry.filled >= entry.capacity;
        return (
          <li key={entry.id} className="relative flex gap-4" style={{ opacity: entry.past ? 0.55 : 1 }}>
            <div className="flex w-[4.75rem] shrink-0 flex-col items-center">
              <span className="whitespace-nowrap text-sm font-bold tabular-nums" style={{ color: "var(--text)" }}>
                {entry.time}
              </span>
              {index < entries.length - 1 ? (
                <span aria-hidden="true" className="mt-2 w-px flex-1" style={{ background: "var(--border)" }} />
              ) : null}
            </div>
            <Link
              href={entry.href}
              className="mb-1 min-w-0 flex-1 rounded-[1.3rem] px-4 py-3 transition-transform hover:-translate-y-0.5"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
            >
              <span className="block truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
                {entry.title}
              </span>
              <span className="mt-2 flex items-center gap-3">
                <span className="h-1.5 flex-1 overflow-hidden rounded-full" style={{ background: "var(--border)" }}>
                  <span
                    className="block h-full rounded-full"
                    style={{ width: `${Math.round(ratio * 100)}%`, background: full ? "var(--success)" : "var(--primary)" }}
                  />
                </span>
                <span className="shrink-0 text-xs tabular-nums" style={{ color: "var(--dim)" }}>
                  {entry.caption}
                </span>
              </span>
            </Link>
          </li>
        );
      })}
    </ol>
  );
}

function initials(name: string) {
  const parts = name.trim().split(/[\s._-]+/).filter(Boolean);
  const letters = parts.length > 1 ? parts[0][0] + parts[1][0] : name.slice(0, 2);
  return letters.toUpperCase();
}

/** People as round initials with their name underneath. */
export function AvatarChips({ people }: { people: Array<{ id: string; name: string; href: string }> }) {
  return (
    <ul className="grid grid-cols-3 gap-3 sm:grid-cols-4">
      {people.map((person) => (
        <li key={person.id} className="min-w-0">
          <Link
            href={person.href}
            className="flex flex-col items-center gap-2 rounded-[1.2rem] px-2 py-3 text-center transition-colors hover:bg-[var(--panel-muted)]"
          >
            <span
              className="grid h-11 w-11 place-items-center rounded-full text-xs font-bold"
              style={{ background: "color-mix(in srgb, var(--primary) 18%, var(--panel))", color: "var(--primary-strong)" }}
              aria-hidden="true"
            >
              {initials(person.name)}
            </span>
            <span className="w-full truncate text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
              {person.name}
            </span>
          </Link>
        </li>
      ))}
    </ul>
  );
}

export type ActionTile = { label: string; href: string; icon: IconName; hint?: string };

/** Big, thumb-friendly shortcuts for the jobs a role does all day. */
export function ActionTiles({ tiles }: { tiles: ActionTile[] }) {
  return (
    <ul className="grid grid-cols-2 gap-3 sm:grid-cols-3">
      {tiles.map((tile) => (
        <li key={tile.href + tile.label} className="min-w-0">
          <Link
            href={tile.href}
            className="flex h-full flex-col gap-3 rounded-[1.4rem] p-4 transition-transform hover:-translate-y-0.5"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
          >
            <span
              className="grid h-10 w-10 place-items-center rounded-2xl"
              style={{ background: "color-mix(in srgb, var(--primary) 14%, transparent)", color: "var(--primary-strong)" }}
            >
              <DashboardIcon name={tile.icon} />
            </span>
            <span className="min-w-0">
              <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>
                {tile.label}
              </span>
              {tile.hint ? (
                <span className="mt-0.5 block text-xs" style={{ color: "var(--dim)" }}>
                  {tile.hint}
                </span>
              ) : null}
            </span>
          </Link>
        </li>
      ))}
    </ul>
  );
}

/** Rows with a status dot and the status in words. */
export function StatusList({
  rows,
}: {
  rows: Array<{ id: string; label: string; status: string; tone: "ok" | "warn" }>;
}) {
  return (
    <ul className="grid gap-2 sm:grid-cols-2">
      {rows.map((row) => (
        <li
          key={row.id}
          className="flex items-center gap-3 rounded-[1.2rem] px-4 py-3"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
        >
          <span
            aria-hidden="true"
            className="h-2.5 w-2.5 shrink-0 rounded-full"
            style={{ background: row.tone === "ok" ? "var(--success)" : "var(--warning)" }}
          />
          <span className="min-w-0 flex-1">
            <span className="block truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
              {row.label}
            </span>
            <span className="block truncate text-xs" style={{ color: "var(--dim)" }}>
              {row.status}
            </span>
          </span>
        </li>
      ))}
    </ul>
  );
}

/** A compact secondary metric: number over label. */
export function StatPill({ label, value, href, warn = false, loading = false }: {
  label: string;
  value: string;
  href: string;
  warn?: boolean;
  loading?: boolean;
}) {
  return (
    <Link
      href={href}
      className="flex min-w-0 flex-col rounded-[1.4rem] px-4 py-3 transition-transform hover:-translate-y-0.5"
      style={{
        background: "var(--panel)",
        border: `1px solid ${warn ? "color-mix(in srgb, var(--danger, var(--primary)) 30%, transparent)" : "var(--border)"}`,
      }}
    >
      <span className="text-lg font-bold tabular-nums" style={{ color: loading ? "var(--border)" : warn ? "var(--danger, var(--primary))" : "var(--text)" }}>
        {loading ? "…" : value}
      </span>
      <span className="truncate text-[11px] font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
        {label}
      </span>
    </Link>
  );
}

export type HubGroup = { label: string; items: Array<{ label: string; href: string; icon: IconName }> };

/** Every page the role can open, as icon tiles grouped by area. */
export function HubTiles({ groups }: { groups: HubGroup[] }) {
  return (
    <section className="grid gap-6 lg:grid-cols-3">
      {groups.map((group) => (
        <div key={group.label} className="rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <p className="text-xs font-semibold uppercase tracking-[0.26em]" style={{ color: "var(--primary-strong)" }}>
            {group.label}
          </p>
          <ul className="mt-4 grid grid-cols-2 gap-2">
            {group.items.map((item) => (
              <li key={item.href} className="min-w-0">
                <Link
                  href={item.href}
                  className="flex h-full items-center gap-2.5 rounded-[1.2rem] px-3 py-3 text-sm font-semibold transition-colors hover:bg-[var(--border)]"
                  style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                >
                  <span className="shrink-0" style={{ color: "var(--primary-strong)" }}>
                    <DashboardIcon name={item.icon} className="h-[18px] w-[18px]" />
                  </span>
                  <span className="min-w-0 break-words leading-tight">{item.label}</span>
                </Link>
              </li>
            ))}
          </ul>
        </div>
      ))}
    </section>
  );
}
