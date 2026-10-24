"use client";

import { useId, useRef, useState } from "react";

import type { PRHistoryEntry, PRRecord, PRUnit } from "@/api/gamification";
import { Popover } from "@/components/ui/Popover";
import { semanticLabel } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatPRCardDetails } from "@/components/pantheon/pr-card-details";
import { chronologicalPRHistory } from "@/components/pantheon/pr-history";
import { trendLine, type PRTrend } from "@/components/pantheon/pr-trend";
import { latestCommentBody } from "@/lib/journal-comments";

export function formatScore(score: number, unit: PRUnit): string {
  if (unit === "mins_secs") {
    const total = Math.round(score);
    const m = String(Math.floor(total / 60)).padStart(2, "0");
    const s = String(total % 60).padStart(2, "0");
    return `${m}:${s}`;
  }
  return Number.isInteger(score) ? String(score) : score.toFixed(2);
}

// The confetti wears the brand's emotion colours (THEME.md: Heat for PRs,
// Spark for energy, Dojo), read as tokens so it follows the theme switch.
const PARTICLE_TOKENS = ["var(--heat)", "var(--spark)", "var(--primary)"] as const;

function lcg(seed: number) {
  let s = seed >>> 0;
  return () => {
    s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
    return s / 4294967295;
  };
}

function hashStr(str: string): number {
  let h = 5381;
  for (let i = 0; i < str.length; i++) {
    h = (((h << 5) + h) ^ str.charCodeAt(i)) >>> 0;
  }
  return h >>> 0;
}

type Particle = { left: string; delay: string; dur: string; color: string; size: number };

function buildParticles(prId: string, count: number): Particle[] {
  const seed = hashStr(prId);
  const rand = lcg(seed);
  return Array.from({ length: count }, () => {
    const token = PARTICLE_TOKENS[Math.floor(rand() * PARTICLE_TOKENS.length)];
    const strength = 55 + Math.floor(rand() * 45);
    return {
      left: `${(rand() * 88 + 6).toFixed(1)}%`,
      delay: `${(rand() * 2.8).toFixed(2)}s`,
      dur: `${(2 + rand() * 1.8).toFixed(2)}s`,
      color: `color-mix(in srgb, ${token} ${strength}%, transparent)`,
      size: 3 + Math.floor(rand() * 6),
    };
  });
}

const PARTICLE_KEYFRAMES = `
@keyframes particle-rise {
  0%   { transform: translateY(0) scale(1);       opacity: 0.8; }
  80%  { opacity: 0.4; }
  100% { transform: translateY(-64px) scale(0.1); opacity: 0; }
}
@media (prefers-reduced-motion: reduce) {
  .pr-particle { animation: none !important; }
}
`;

function Particles({ prId }: { prId: string }) {
  const particles = buildParticles(prId, 15);
  return (
    <>
      <style>{PARTICLE_KEYFRAMES}</style>
      {particles.map((p, i) => (
        <span
          key={i}
          aria-hidden="true"
          className="pr-particle pointer-events-none absolute bottom-1 rounded-full"
          style={{
            left: p.left,
            width: p.size,
            height: p.size,
            background: p.color,
            opacity: 0,
            animation: `particle-rise ${p.dur} ${p.delay} ease-out infinite`,
          }}
        />
      ))}
    </>
  );
}

/** The signed change in the PR's own unit: «+7.5», «−0:18». */
function formatChange(change: number, unit: PRUnit, locale: string): string {
  const sign = change > 0 ? "+" : "−";
  const size = Math.abs(change);
  const text =
    unit === "mins_secs"
      ? formatScore(size, unit).replace(/^0(\d:)/, "$1")
      : new Intl.NumberFormat(locale, { maximumFractionDigits: 1 }).format(size);
  return `${sign}${text}`;
}

/**
 * The trend row of a PR (ADR-194): a small line of the range (estimated 1RM
 * for a lift), the latest value and the change, and «retest» for a
 * benchmark not beaten for a while. A tap opens the score history.
 */
function TrendRow({ pr, trend, history }: { pr: PRRecord; trend: PRTrend | null; history: PRHistoryEntry[] }) {
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const anchorRef = useRef<HTMLButtonElement>(null);
  const popoverId = useId();
  const [open, setOpen] = useState(false);
  const line = trend ? trendLine(trend.points, pr.higher_is_better, 64, 16) : null;
  const unitLabel = semanticLabel(pr.unit, i18n);
  const rawChange = trend?.improvement == null ? null : pr.higher_is_better ? trend.improvement : -trend.improvement;
  const hasHistory = history.length > 0;
  // A single lift with reps still says something: its estimated 1RM.
  const estimate = trend?.kind === "strength" && (hasHistory || Number(pr.supporting_metrics?.reps ?? 1) > 1);
  if (!hasHistory && !trend?.retestDue && !estimate) return null;

  const rowClass = "mt-2 flex min-h-11 w-full flex-wrap items-center gap-x-2 gap-y-1 rounded-xl px-2 text-start text-xs";
  const rowStyle = { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" };
  const content = (
    <>
      {line ? (
        <svg width="64" height="16" viewBox="-2 -2 68 20" aria-hidden="true" className="shrink-0 overflow-visible">
          <polyline points={line} fill="none" stroke="var(--primary)" strokeWidth="2" strokeLinejoin="round" strokeLinecap="round" />
        </svg>
      ) : null}
      {trend && estimate ? (
        <span className="tabular-nums">
          {i18n("prTrendEstimated", {
            value: new Intl.NumberFormat(uiLocale, { maximumFractionDigits: 1 }).format(trend.latest),
            unit: unitLabel,
          })}
        </span>
      ) : null}
      {rawChange !== null ? (
        <span
          className="rounded-full px-1.5 font-semibold tabular-nums"
          style={{
            background: "var(--panel-muted)",
            color: trend && trend.improvement !== null && trend.improvement > 0 ? "var(--success)" : "var(--muted)",
          }}
        >
          <bdi>{formatChange(rawChange, pr.unit, uiLocale)}</bdi>
        </span>
      ) : null}
      {trend?.retestDue ? <span style={{ color: "var(--muted)" }}>{i18n("prTrendRetest")}</span> : null}
      {hasHistory ? (
        <span className="ms-auto font-semibold" style={{ color: "var(--primary)" }}>
          {i18n("scoreHistorydb246b2")}
        </span>
      ) : null}
    </>
  );
  if (!hasHistory) {
    return (
      <div className={rowClass} style={rowStyle}>
        {content}
      </div>
    );
  }

  return (
    <>
      <button
        ref={anchorRef}
        type="button"
        aria-haspopup="dialog"
        aria-expanded={open}
        aria-controls={open ? popoverId : undefined}
        onClick={(event) => {
          event.stopPropagation();
          setOpen((value) => !value);
        }}
        className={rowClass}
        style={rowStyle}
      >
        {content}
      </button>
      <Popover
        anchorRef={anchorRef}
        open={open}
        onClose={() => setOpen(false)}
        role="dialog"
        id={popoverId}
        ariaLabel={`${pr.name} · ${i18n("scoreHistorydb246b2")}`}
        width={280}
        className="rounded-2xl p-3"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", boxShadow: "var(--shadow-md)", maxHeight: "16rem" }}
      >
        {/* The popover renders in a portal; keep its taps from opening the card. */}
        <div onClick={(event) => event.stopPropagation()}>
          <p className="mb-2 text-[10px] font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {i18n("scoreHistorydb246b2")}
          </p>
          <ol className="flex flex-col gap-2">
            {chronologicalPRHistory(pr, history).map((entry) => (
              <li
                key={entry.id}
                className="flex items-center justify-between gap-3 rounded-lg px-2.5 py-1"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
              >
                <span className="text-xs font-bold tabular-nums" style={{ color: "var(--heat)" }}>
                  {formatScore(Number(entry.score), pr.unit)}
                </span>
                <time dateTime={entry.beaten_on} className="text-[10px]" style={{ color: "var(--dim)" }}>
                  {new Date(entry.beaten_on).toLocaleDateString(uiLocale, { year: "numeric", month: "short", day: "numeric" })}
                </time>
              </li>
            ))}
          </ol>
        </div>
      </Popover>
    </>
  );
}

/** A small line-icon action in a card's corner that doesn't open the card; a full 44px target. */
function CardIconButton({ label, onClick, children }: { label: string; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={(event) => {
        event.stopPropagation();
        onClick();
      }}
      aria-label={label}
      title={label}
      className="flex h-11 w-11 items-center justify-center rounded-full"
      style={{ color: "var(--dim)" }}
    >
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        {children}
      </svg>
    </button>
  );
}

/**
 * A PR in Πρόοδος › Personal Records: name, score, date and details; a tap
 * edits it, the corner shares or deletes it, and the trend row (ADR-194)
 * shows the range's line and opens the score history in a popover.
 */
export function PantheonCard({
  pr,
  trend = null,
  history = [],
  onEdit,
  onDelete,
  onShare,
}: {
  pr: PRRecord;
  trend?: PRTrend | null;
  /** This PR's superseded scores (from the one history read). */
  history?: PRHistoryEntry[];
  onEdit?: (pr: PRRecord) => void;
  onDelete?: (pr: PRRecord) => void;
  onShare?: (pr: PRRecord) => void;
}) {
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const scoreStr = formatScore(Number(pr.current_score), pr.unit);
  const unitLabel = semanticLabel(pr.unit, i18n);
  const dateStr = new Date(pr.beaten_on).toLocaleDateString(uiLocale, {
    month: "short", day: "numeric", year: "numeric",
  });
  const details = formatPRCardDetails(pr.supporting_metrics ?? {}, i18n);
  const latestComment = latestCommentBody(pr.comments);

  return (
    <div
      className={"relative overflow-hidden rounded-[1.5rem] px-5 py-4 " + (onEdit ? "cursor-pointer transition-transform hover:-translate-y-0.5" : "")}
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
      onClick={() => onEdit?.(pr)}
      onKeyDown={(event) => {
        if (event.target !== event.currentTarget) return;
        if (onEdit && (event.key === "Enter" || event.key === " ")) {
          event.preventDefault();
          onEdit(pr);
        }
      }}
      role={onEdit ? "button" : undefined}
      tabIndex={onEdit ? 0 : undefined}
      aria-label={onEdit ? i18n("updatefb91e24") + (pr.name) + i18n("personalRecord3b9dbf2") : undefined}
    >
      <Particles prId={pr.id} />

      {onShare || onDelete ? (
        <div className="absolute top-1 end-1 flex">
          {onShare ? (
            <CardIconButton label={i18n("sharePrf54c0df")} onClick={() => onShare(pr)}>
              <path d="M4 12v7a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-7M16 6l-4-4-4 4M12 2v13" />
            </CardIconButton>
          ) : null}
          {onDelete ? (
            <CardIconButton label={i18n("deletef6fdbe4")} onClick={() => onDelete(pr)}>
              <path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6" />
            </CardIconButton>
          ) : null}
        </div>
      ) : null}

      <p className="text-sm font-semibold truncate pe-20" style={{ color: "var(--text)" }}>{pr.name}</p>
      <div className="mt-1.5 flex items-baseline gap-1.5">
        <span className="text-2xl font-bold tabular-nums" style={{ color: "var(--heat)" }}>{scoreStr}</span>
        <span className="text-xs font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{unitLabel}</span>
      </div>
      <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{dateStr}</p>
      {(details || latestComment) && (
        <div className="mt-2 border-s-2 ps-2" style={{ borderColor: "var(--heat)" }}>
          {details && <p className="truncate text-[11px]" style={{ color: "var(--text-soft)" }}>{details}</p>}
          {latestComment && <p className="mt-0.5 truncate text-[11px]" style={{ color: "var(--muted)" }}>{latestComment}</p>}
        </div>
      )}
      <TrendRow pr={pr} trend={trend} history={history} />
    </div>
  );
}
