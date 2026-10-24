"use client";

import type { CSSProperties, ReactNode } from "react";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { SPARK_ACTIVE_STYLE } from "@/lib/spark";
import type { GuideAnchor } from "@/lib/guides/anchors";

// Small presentational pieces shared by the staff screens, styled like the
// existing admin panels.

export const inputClass = "w-full rounded-xl px-3 py-2 text-sm";
export const inputStyle: CSSProperties = {
  background: "var(--panel-muted)",
  border: "1px solid var(--border-strong)",
  color: "var(--text)",
};
export const captionClass = "block text-xs font-semibold";
export const captionStyle: CSSProperties = { color: "var(--dim)", letterSpacing: "0.18em", textTransform: "uppercase" };

export const primaryButtonClass = "rounded-full px-5 py-2.5 text-sm font-semibold disabled:opacity-50";
export const primaryButtonStyle: CSSProperties = { background: "var(--primary)", color: "var(--primary-contrast)" };
export const secondaryButtonClass = "rounded-full px-3 py-1.5 text-xs font-semibold disabled:opacity-50";
export const secondaryButtonStyle: CSSProperties = {
  background: "var(--border)",
  border: "1px solid var(--border-strong)",
  color: "var(--text-soft)",
};
export const dangerButtonStyle: CSSProperties = {
  background: "color-mix(in srgb, var(--danger) 10%, transparent)",
  border: "1px solid color-mix(in srgb, var(--danger) 24%, transparent)",
  color: "var(--danger)",
};

export function StaffPanel({
  title,
  eyebrow,
  actions,
  children,
  labelledBy,
  guide,
}: {
  title: ReactNode;
  eyebrow?: ReactNode;
  actions?: ReactNode;
  children: ReactNode;
  labelledBy: string;
  /** A walkthrough anchor (ADR-193). */
  guide?: GuideAnchor;
}) {
  return (
    <section
      aria-labelledby={labelledBy}
      data-guide={guide}
      className="rounded-[2rem] p-5 md:p-6"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          {eyebrow ? (
            <p className="text-xs font-bold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>
              {eyebrow}
            </p>
          ) : null}
          <h2 id={labelledBy} className="mt-1 text-xl font-semibold" style={{ color: "var(--text)" }}>
            {title}
          </h2>
        </div>
        {actions ? <div className="flex flex-wrap gap-2">{actions}</div> : null}
      </div>
      <div className="mt-4">{children}</div>
    </section>
  );
}

export function StatusText({ tone, children }: { tone: "error" | "success" | "muted"; children: ReactNode }) {
  if (tone === "error") return <ErrorNotice>{children}</ErrorNotice>;
  const color = tone === "success" ? "var(--success)" : "var(--muted)";
  return (
    <p className="text-sm" role="status" style={{ color }}>
      {children}
    </p>
  );
}

export function Pill({ tone, children }: { tone: "danger" | "warning" | "success" | "neutral" | "primary" | "spark"; children: ReactNode }) {
  // Spark: live and active things, a fill with dark text (docs/brand/THEME.md).
  if (tone === "spark") {
    return (
      <span className="inline-flex shrink-0 items-center rounded-full px-2.5 py-0.5 text-[11px] font-semibold uppercase tracking-[0.14em]" style={SPARK_ACTIVE_STYLE}>
        {children}
      </span>
    );
  }
  const color =
    tone === "danger"
      ? "var(--danger)"
      : tone === "warning"
        ? "var(--warning)"
        : tone === "success"
          ? "var(--success)"
          : tone === "primary"
            ? "var(--primary)"
            : "var(--muted)";
  return (
    <span
      className="inline-flex shrink-0 items-center rounded-full px-2.5 py-0.5 text-[11px] font-semibold uppercase tracking-[0.14em]"
      style={{ color, background: `color-mix(in srgb, ${color} 12%, transparent)` }}
    >
      {children}
    </span>
  );
}
