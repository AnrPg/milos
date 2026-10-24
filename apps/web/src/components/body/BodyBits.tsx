"use client";

import { useState, type ReactNode } from "react";
import { useTranslations } from "next-intl";

import type { BodyCatalogEntry, BodyMetric, BodyPhoto, BodySnapshot } from "@/api/body";
import { formatDelta, formatMetric, unitOf } from "@/lib/body";

/** Joins key parts, so dynamic message keys stay plain strings. */
export const key = (...parts: string[]) => parts.join(".");

export function Card({ children, label, className = "" }: { children: ReactNode; label?: string; className?: string }) {
  return (
    <section
      aria-label={label}
      className={["flex flex-col gap-3 rounded-2xl p-4", className].join(" ")}
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      {children}
    </section>
  );
}

export function Eyebrow({ children }: { children: ReactNode }) {
  return (
    <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
      {children}
    </p>
  );
}

export function Chip({ selected, onClick, children }: { selected: boolean; onClick: () => void; children: ReactNode }) {
  return (
    <button
      type="button"
      aria-pressed={selected}
      onClick={onClick}
      className="min-h-11 rounded-full px-3 py-1 text-sm font-semibold"
      style={{
        background: selected ? "var(--primary)" : "var(--panel-raised)",
        color: selected ? "var(--primary-contrast)" : "var(--text)",
        border: "1px solid var(--border)",
      }}
    >
      {children}
    </button>
  );
}

export function PillButton({
  children,
  onClick,
  primary,
  disabled,
  type = "button",
  danger,
}: {
  children: ReactNode;
  onClick?: () => void;
  primary?: boolean;
  disabled?: boolean;
  type?: "button" | "submit";
  danger?: boolean;
}) {
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      className="min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
      style={{
        background: primary ? "var(--primary)" : "var(--panel-raised)",
        color: primary ? "var(--primary-contrast)" : danger ? "var(--danger)" : "var(--text)",
        border: primary ? "none" : "1px solid var(--border)",
      }}
    >
      {children}
    </button>
  );
}

export function LockIcon() {
  return (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
      <rect x="5" y="11" width="14" height="10" rx="2" />
      <path d="M8 11V7a4 4 0 0 1 8 0v4" />
    </svg>
  );
}

/** The share icon: a line arrow out of a box (no text; the button carries an aria-label). */
export function ShareIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M12 3v12" />
      <path d="m7 8 5-5 5 5" />
      <path d="M5 13v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6" />
    </svg>
  );
}

/** A subtle line-icon button with no visible text. */
export function IconButton({ label, onClick, children }: { label: string; onClick: () => void; children: ReactNode }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      onClick={onClick}
      className="hit-area inline-flex h-9 w-9 items-center justify-center rounded-full"
      style={{ color: "var(--dim)", border: "1px solid var(--border)", background: "transparent" }}
    >
      {children}
    </button>
  );
}

export function PrivacyLine({ children }: { children: ReactNode }) {
  return (
    <p className="flex items-center gap-1.5 text-xs" style={{ color: "var(--dim)" }}>
      <LockIcon />
      {children}
    </p>
  );
}

/**
 * One private body photo. With «θολές μέχρι να τις πατήσεις» on, it shows
 * blurred until tapped; processing and failed photos say so.
 */
export function BodyPhotoView({
  photo,
  blur,
  label,
  size = "feed",
  className = "",
  fit = "cover",
}: {
  photo: BodyPhoto | null | undefined;
  blur: boolean;
  label: string;
  size?: "thumb" | "feed" | "full";
  className?: string;
  fit?: "cover" | "contain";
}) {
  const t = useTranslations("Body");
  const [revealed, setRevealed] = useState(false);
  const url = photo ? (size === "thumb" ? photo.thumb_url : size === "full" ? (photo.full_url ?? photo.feed_url) : (photo.feed_url ?? photo.thumb_url)) : null;
  const frame = ["relative overflow-hidden rounded-xl", className].join(" ");
  const style = { background: "linear-gradient(160deg, var(--deep), var(--media))" };

  if (!photo || photo.status !== "ready" || !url) {
    return (
      <div className={frame} style={style} data-testid="body-photo-empty">
        <span className="absolute inset-x-1 bottom-1 truncate text-[10px] font-bold text-[var(--on-media)]">
          {photo?.status === "processing" ? t("photoProcessing") : photo?.status === "failed" ? t("photoFailed") : label}
        </span>
      </div>
    );
  }

  const hidden = blur && !revealed;
  return (
    <div className={frame} style={style} data-testid="body-photo" data-blurred={hidden ? "true" : "false"}>
      {/* eslint-disable-next-line @next/next/no-img-element -- short-lived presigned URL */}
      <img
        src={url}
        alt={label}
        className={["h-full w-full", fit === "contain" ? "object-contain" : "object-cover"].join(" ")}
        style={hidden ? { filter: "blur(18px)", transform: "scale(1.1)" } : undefined}
        draggable={false}
      />
      {hidden ? (
        <button
          type="button"
          onClick={() => setRevealed(true)}
          className="absolute inset-0 flex items-center justify-center text-xs font-bold text-[var(--on-media)]"
          aria-label={t("revealPhoto", { label })}
        >
          <span className="rounded-full px-2 py-1" style={{ background: "var(--media-control)" }}>{t("tapToShow")}</span>
        </button>
      ) : null}
    </div>
  );
}

/** «72,4 kg» or nothing; withheld metrics never get a number. */
export function MetricValue({
  snapshot,
  metric,
  catalog,
  locale,
}: {
  snapshot: Pick<BodySnapshot, "metrics" | "withheld_metrics" | "units">;
  metric: BodyMetric;
  catalog: BodyCatalogEntry[];
  locale: string;
}) {
  const t = useTranslations("Body");
  const value = snapshot.metrics[metric];
  if (typeof value === "number") return <span className="tabular-nums">{formatMetric(value, unitOf(metric, catalog, snapshot.units), locale)}</span>;
  if (snapshot.withheld_metrics.includes(metric)) return <span style={{ color: "var(--dim)" }}>{t("trendOnly")}</span>;
  return null;
}

export function DeltaBadge({ delta, unit, locale }: { delta: number; unit: string; locale: string }) {
  return (
    <span
      className="shrink-0 rounded-full px-2 py-0.5 text-xs font-bold tabular-nums"
      style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
    >
      {formatDelta(delta, unit, locale)}
    </span>
  );
}

export function dateFormat(locale: string) {
  return {
    day: (iso: string) => new Intl.DateTimeFormat(locale, { day: "numeric", month: "short" }).format(new Date(iso)),
    dayYear: (iso: string) => new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", year: "numeric" }).format(new Date(iso)),
    dateTime: (iso: string) =>
      new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }).format(new Date(iso)),
  };
}
