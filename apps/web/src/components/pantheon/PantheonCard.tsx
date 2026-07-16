"use client";





import {useUiTranslations} from "@/i18n/ui";
import { useState, useRef, useEffect, useCallback } from "react";
import { createPortal } from "react-dom";
import { useQuery } from "@tanstack/react-query";
import { getPRHistory, type PRRecord, type PRUnit } from "@/api/gamification";
import { useSession } from "@/components/session-provider";

export function formatScore(score: number, unit: PRUnit): string {
  if (unit === "mins_secs") {
    const total = Math.round(score);
    const m = String(Math.floor(total / 60)).padStart(2, "0");
    const s = String(total % 60).padStart(2, "0");
    return `${m}:${s}`;
  }
  return Number.isInteger(score) ? String(score) : score.toFixed(2);
}

const UNIT_LABELS: Record<PRUnit, string> = {
  mins_secs: "min:sec",
  reps: "reps",
  sets: "sets",
  kcals: "kcal",
  m: "m",
  kg: "kg",
};

// Palette hues: primary/purple, amber, green, teal, pink, red, indigo, gold
const PALETTE_HUES = [260, 40, 155, 200, 320, 10, 280, 55];

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
  const baseHue = PALETTE_HUES[seed % PALETTE_HUES.length];
  return Array.from({ length: count }, () => ({
    left: `${(rand() * 88 + 6).toFixed(1)}%`,
    delay: `${(rand() * 2.8).toFixed(2)}s`,
    dur: `${(2 + rand() * 1.8).toFixed(2)}s`,
    color: `hsl(${((baseHue + rand() * 42 - 21 + 360) % 360).toFixed(0)}, ${(65 + rand() * 30).toFixed(0)}%, ${(52 + rand() * 22).toFixed(0)}%)`,
    size: 3 + Math.floor(rand() * 6),
  }));
}

const PARTICLE_KEYFRAMES = `
@keyframes particle-rise {
  0%   { transform: translateY(0) scale(1);       opacity: 0.8; }
  80%  { opacity: 0.4; }
  100% { transform: translateY(-64px) scale(0.1); opacity: 0; }
}
`;

function Particles({ prId }: { prId: string }) {
  const i18n = useUiTranslations();
  const particles = buildParticles(prId, 15);
  return (
    <>
      <style>{PARTICLE_KEYFRAMES}</style>
      {particles.map((p, i) => (
        <span
          key={i}
          className="pointer-events-none absolute bottom-1 rounded-full"
          style={{
            left: p.left,
            width: p.size,
            height: p.size,
            background: p.color,
            opacity: 0,
            animation: "particle-rise " + (p.dur) + " " + (p.delay) + " ease-out infinite",
          }}
        />
      ))}
    </>
  );
}

// ── Tooltip ────────────────────────────────────────────────────────────────

interface TooltipPos { top: number; left: number }

function PRHistoryTooltip({
  prId,
  unit,
  children,
}: {
  prId: string;
  unit: PRUnit;
  children: React.ReactNode;
}) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const [open, setOpen] = useState(false);
  const [pos, setPos] = useState<TooltipPos>({ top: 0, left: 0 });
  const triggerRef = useRef<HTMLDivElement>(null);
  const openTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const closeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    queueMicrotask(() => setMounted(true));
  }, []);

  const historyQuery = useQuery({
    queryKey: ["prs", prId, "history"],
    enabled: open && Boolean(tokens?.access_token),
    queryFn: async () => getPRHistory(tokens!.access_token, prId),
    staleTime: 60_000,
  });

  const computePos = useCallback((clientX: number, clientY: number) => {
    const GAP = 12;
    const TOOLTIP_W = 300;
    const TOOLTIP_H = 220;
    const viewportPad = 8;

    const opensRight = clientX + GAP + TOOLTIP_W <= window.innerWidth - viewportPad;
    const opensDown = clientY + GAP + TOOLTIP_H <= window.innerHeight - viewportPad;

    const left = opensRight
      ? clientX + window.scrollX + GAP
      : clientX + window.scrollX - TOOLTIP_W - GAP;
    const top = opensDown
      ? clientY + window.scrollY + GAP
      : clientY + window.scrollY - TOOLTIP_H - GAP;

    setPos({
      left: Math.max(window.scrollX + viewportPad, left),
      top: Math.max(window.scrollY + viewportPad, top),
    });
  }, []);

  const handleEnter = (event: React.MouseEvent<HTMLDivElement>) => {
    if (closeTimer.current) clearTimeout(closeTimer.current);
    const { clientX, clientY } = event;
    openTimer.current = setTimeout(() => { computePos(clientX, clientY); setOpen(true); }, 200);
  };

  const handleMove = (event: React.MouseEvent<HTMLDivElement>) => {
    if (!open) return;
    computePos(event.clientX, event.clientY);
  };

  const handleLeave = () => {
    if (openTimer.current) clearTimeout(openTimer.current);
    closeTimer.current = setTimeout(() => setOpen(false), 120);
  };

  useEffect(() => () => {
    if (openTimer.current) clearTimeout(openTimer.current);
    if (closeTimer.current) clearTimeout(closeTimer.current);
  }, []);

  const historyEntries = historyQuery.data
    ? [...historyQuery.data].sort(
      (a, b) => new Date(b.beaten_on).getTime() - new Date(a.beaten_on).getTime(),
    )
    : [];

  return (
    <>
      <div
        ref={triggerRef}
        className="cursor-inherit"
        onMouseEnter={handleEnter}
        onMouseMove={handleMove}
        onMouseLeave={handleLeave}
      >
        {children}
      </div>

      {mounted && open && createPortal(
        <div
          onMouseEnter={() => {
            if (closeTimer.current) clearTimeout(closeTimer.current);
          }}
          onMouseLeave={handleLeave}
          style={{
            position: "absolute",
            top: pos.top,
            left: pos.left,
            zIndex: 9999,
            width: 300,
            background: "var(--panel)",
            border: "1px solid var(--border)",
            borderRadius: "1rem",
            padding: "12px 16px",
            boxShadow: "0 16px 48px rgba(0,0,0,0.5)",
          }}
        >
          <p className="text-[10px] font-semibold uppercase tracking-[0.18em] mb-2" style={{ color: "var(--dim)" }}>
            {i18n("scoreHistorydb246b2")}
          </p>
          {historyQuery.isPending ? (
            <p className="text-xs" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
          ) : historyEntries.length === 0 ? (
            <p className="text-xs" style={{ color: "var(--dim)" }}>{i18n("noHistoryYet933f417")}</p>
          ) : (
            <div className="flex flex-col gap-2">
              {historyEntries.slice(0, 10).map((entry) => (
                <div
                  key={entry.id}
                  className="flex items-center justify-between gap-3 rounded-lg px-2.5 py-1"
                  style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
                >
                  <span className="text-xs font-bold tabular-nums" style={{ color: "var(--primary)" }}>
                    {formatScore(Number(entry.score), unit)}
                  </span>
                  <span className="text-[10px]" style={{ color: "var(--dim)" }}>
                    {new Date(entry.beaten_on).toLocaleDateString(undefined, { month: "short", day: "numeric" })}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>,
        document.body,
      )}
    </>
  );
}

// ── Cards ──────────────────────────────────────────────────────────────────

function CompactCard({
  pr,
  onEdit,
  onShare,
}: {
  pr: PRRecord;
  onEdit?: (pr: PRRecord) => void;
  onShare?: (pr: PRRecord) => void;
}) {
  const i18n = useUiTranslations();
  const scoreStr = formatScore(Number(pr.current_score), pr.unit);
  const unitLabel = UNIT_LABELS[pr.unit] ?? pr.unit;
  const dateStr = new Date(pr.beaten_on).toLocaleDateString(undefined, {
    month: "short", day: "numeric", year: "numeric",
  });

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

      {onShare && (
        <button
          type="button"
          onClick={(event) => {
            event.stopPropagation();
            onShare(pr);
          }}
          className="absolute top-3 right-3 rounded-lg px-2 py-1 text-[10px] font-semibold opacity-50 hover:opacity-90 transition-opacity"
          style={{ background: "var(--border)", color: "var(--dim)" }}
          title={i18n("sharePrf54c0df")}
        >
          🔗
        </button>
      )}

      <PRHistoryTooltip prId={pr.id} unit={pr.unit}>
        <div>
          <p className="text-sm font-semibold truncate pr-8" style={{ color: "var(--text)" }}>{pr.name}</p>
          <div className="mt-1.5 flex items-baseline gap-1.5">
            <span className="text-2xl font-bold tabular-nums" style={{ color: "var(--primary)" }}>{scoreStr}</span>
            <span className="text-xs font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{unitLabel}</span>
          </div>
          <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{dateStr}</p>
        </div>
      </PRHistoryTooltip>
    </div>
  );
}

function FullCard({
  pr,
  onEdit,
  onDelete,
  onShare,
}: {
  pr: PRRecord;
  onEdit?: (pr: PRRecord) => void;
  onDelete?: (pr: PRRecord) => void;
  onShare?: (pr: PRRecord) => void;
}) {
  const i18n = useUiTranslations();
  const scoreStr = formatScore(Number(pr.current_score), pr.unit);
  const unitLabel = UNIT_LABELS[pr.unit] ?? pr.unit;
  const dateStr = new Date(pr.beaten_on).toLocaleDateString(undefined, {
    month: "short", day: "numeric", year: "numeric",
  });

  return (
    <div
      className={"relative overflow-hidden rounded-[1.8rem] p-5 pb-14 " + (onEdit ? "cursor-pointer transition-transform hover:-translate-y-0.5" : "")}
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

      {/* Share — top right */}
      {onShare && (
        <button
          type="button"
          onClick={(event) => {
            event.stopPropagation();
            onShare(pr);
          }}
          className="absolute top-4 right-4 rounded-xl px-3 py-1.5 text-sm font-semibold"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          title={i18n("sharePrf54c0df")}
        >
          {i18n("share02e24e8")}
        </button>
      )}

      {/* PR data — padded right to avoid overlap with Share button */}
      <PRHistoryTooltip prId={pr.id} unit={pr.unit}>
        <div className="min-w-0 pr-28">
          <p className="font-semibold truncate" style={{ color: "var(--text)" }}>{pr.name}</p>
          <div className="mt-1.5 flex items-baseline gap-1.5">
            <span className="text-3xl font-bold tabular-nums" style={{ color: "var(--primary)" }}>{scoreStr}</span>
            <span className="text-xs font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{unitLabel}</span>
          </div>
          <p className="mt-1.5 text-xs" style={{ color: "var(--dim)" }}>
            {pr.higher_is_better ? i18n("higherIsBetter7aab104") : i18n("lowerIsBettercf052ba")} · {dateStr}
          </p>
        </div>
      </PRHistoryTooltip>

      {/* Edit + Delete — bottom right, side-by-side */}
      {(onEdit || onDelete) && (
        <div className="absolute bottom-4 right-4 flex gap-2">
          {onEdit && (
            <button
              type="button"
              onClick={(event) => {
                event.stopPropagation();
                onEdit(pr);
              }}
              className="rounded-xl w-9 h-9 flex items-center justify-center text-base"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
              title={i18n("updatePr71b8cf3")}
            >
              🔄
            </button>
          )}
          {onDelete && (
            <button
              type="button"
              onClick={(event) => {
                event.stopPropagation();
                onDelete(pr);
              }}
              className="rounded-xl w-9 h-9 flex items-center justify-center text-base"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
              title={i18n("deletef6fdbe4")}
            >
              🗑️
            </button>
          )}
        </div>
      )}
    </div>
  );
}

export function PantheonCard({
  pr,
  compact = false,
  onEdit,
  onDelete,
  onShare,
}: {
  pr: PRRecord;
  compact?: boolean;
  onEdit?: (pr: PRRecord) => void;
  onDelete?: (pr: PRRecord) => void;
  onShare?: (pr: PRRecord) => void;
}) {
  if (compact) return <CompactCard pr={pr} onEdit={onEdit} onShare={onShare} />;
  return <FullCard pr={pr} onEdit={onEdit} onDelete={onDelete} onShare={onShare} />;
}
