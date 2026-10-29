import type { CSSProperties, ReactNode } from "react";

/** Small pieces the fiscal screens share (mockups s1 and s2), theme colours only. */

export type Tone = "neutral" | "ok" | "warn" | "bad" | "accent" | "info";

const TONE: Record<Tone, CSSProperties> = {
  neutral: { background: "var(--panel-muted)", color: "var(--text-soft)" },
  ok: { background: "color-mix(in srgb, var(--success) 16%, transparent)", color: "var(--success)" },
  warn: { background: "color-mix(in srgb, var(--warning) 16%, transparent)", color: "var(--warning)" },
  bad: { background: "color-mix(in srgb, var(--danger) 14%, transparent)", color: "var(--danger)" },
  accent: { background: "color-mix(in srgb, var(--primary) 14%, transparent)", color: "var(--primary-strong)" },
  info: { background: "color-mix(in srgb, var(--info) 16%, transparent)", color: "var(--info)" },
};

export function Pill({ tone = "neutral", children, testId }: { tone?: Tone; children: ReactNode; testId?: string }) {
  return (
    <span
      data-testid={testId}
      className="inline-flex items-center gap-1 whitespace-nowrap rounded-full px-2 py-0.5 text-[11px] font-bold"
      style={TONE[tone]}
    >
      {children}
    </span>
  );
}

export function Card({ children, className = "", style, testId }: { children: ReactNode; className?: string; style?: CSSProperties; testId?: string }) {
  return (
    <section
      data-testid={testId}
      className={`grid min-w-0 gap-3 rounded-[18px] px-4 py-4 sm:px-5 ${className}`}
      style={{ background: "var(--panel)", border: "1px solid var(--border)", ...style }}
    >
      {children}
    </section>
  );
}

/** «Λείπουν…» as a ring: the share of the checklist that is done. */
export function Ring({ percent, label }: { percent: number; label: string }) {
  return (
    <span
      role="img"
      aria-label={label}
      className="relative grid h-12 w-12 flex-none place-items-center rounded-full font-mono text-xs font-extrabold"
      style={{ background: `conic-gradient(var(--success) ${percent}%, var(--panel-muted) 0)` }}
    >
      <span aria-hidden="true" className="absolute inset-[5px] rounded-full" style={{ background: "var(--bg)" }} />
      <b aria-hidden="true" className="relative" style={{ color: "var(--text)" }}>{percent}%</b>
    </span>
  );
}

export function KeyValue({ label, children, total = false }: { label: ReactNode; children: ReactNode; total?: boolean }) {
  return (
    <div
      className={`flex justify-between gap-2 py-0.5 ${total ? "mt-1 pt-2 text-sm font-extrabold" : "text-[13px]"}`}
      style={total ? { color: "var(--text)", borderTop: "1px solid var(--border)" } : { color: "var(--text-soft)" }}
    >
      <span className="min-w-0">{label}</span>
      <span className="whitespace-nowrap font-mono">{children}</span>
    </div>
  );
}

export const hintStyle: CSSProperties = { color: "var(--muted)" };

export const ghostButtonClass =
  "inline-flex min-h-10 items-center justify-center gap-1.5 rounded-full px-4 text-sm font-bold disabled:opacity-50";
export const ghostButtonStyle: CSSProperties = { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" };
export const primaryButtonStyle: CSSProperties = { background: "var(--primary)", color: "var(--primary-contrast)", border: "1px solid var(--primary)" };
export const dangerButtonStyle: CSSProperties = { background: "var(--danger)", color: "var(--danger-contrast)", border: "1px solid var(--danger)" };
export const linkButtonClass = "inline-flex items-center gap-1 text-sm font-bold";
export const linkButtonStyle: CSSProperties = { color: "var(--primary-strong)" };

/** Money in a document's currency, from integer cents. */
export function formatMoney(locale: string, cents: number, currency: string) {
  return new Intl.NumberFormat(locale, { style: "currency", currency }).format(cents / 100);
}

/** A country's name in the viewer's language. */
export function countryName(locale: string, code: string) {
  try {
    return new Intl.DisplayNames([locale], { type: "region" }).of(code) ?? code;
  } catch {
    return code;
  }
}
