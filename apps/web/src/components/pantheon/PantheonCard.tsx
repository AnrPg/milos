"use client";

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
            animation: `particle-rise ${p.dur} ${p.delay} ease-out infinite`,
          }}
        />
      ))}
    </>
  );
}

// ── Tooltip ────────────────────────────────────────────────────────────────

interface TooltipPos { top: number; left: number; placement: "top" | "bottom" }

function PRHistoryTooltip({
  prId,
  unit,
  children,
}: {
  prId: string;
  unit: PRUnit;
  children: React.ReactNode;
}) {
  const { tokens } = useSession();
  const [open, setOpen] = useState(false);
  const [pos, setPos] = useState<TooltipPos>({ top: 0, left: 0, placement: "top" });
  const triggerRef = useRef<HTMLDivElement>(null);
  const openTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const closeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [mounted, setMounted] = useState(false);

  useEffect(() => { setMounted(true); }, []);

  const historyQuery = useQuery({
    queryKey: ["prs", prId, "history"],
    enabled: open && Boolean(tokens?.access_token),
    queryFn: async () => getPRHistory(tokens!.access_token, prId),
    staleTime: 60_000,
  });

  const computePos = useCallback(() => {
    if (!triggerRef.current) return;
    const rect = triggerRef.current.getBoundingClientRect();
    const GAP = 8;
    const TOOLTIP_H = 140;
    const spaceAbove = rect.top;
    const placement: "top" | "bottom" = spaceAbove >= TOOLTIP_H + GAP ? "top" : "bottom";
    const top = placement === "top"
      ? rect.top + window.scrollY - TOOLTIP_H - GAP
      : rect.bottom + window.scrollY + GAP;
    const left = Math.max(8, Math.min(rect.left + window.scrollX, window.innerWidth - 336));
    setPos({ top, left, placement });
  }, []);

  const handleEnter = () => {
    if (closeTimer.current) clearTimeout(closeTimer.current);
    openTimer.current = setTimeout(() => { computePos(); setOpen(true); }, 200);
  };

  const handleLeave = () => {
    if (openTimer.current) clearTimeout(openTimer.current);
    closeTimer.current = setTimeout(() => setOpen(false), 120);
  };

  useEffect(() => () => {
    if (openTimer.current) clearTimeout(openTimer.current);
    if (closeTimer.current) clearTimeout(closeTimer.current);
  }, []);

  return (
    <>
      <div
        ref={triggerRef}
        className="cursor-default"
        onMouseEnter={handleEnter}
        onMouseLeave={handleLeave}
      >
        {children}
      </div>

      {mounted && open && createPortal(
        <div
          onMouseEnter={handleEnter}
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
            Score history
          </p>
          {historyQuery.isPending ? (
            <p className="text-xs" style={{ color: "var(--dim)" }}>Loading…</p>
          ) : !historyQuery.data || historyQuery.data.length === 0 ? (
            <p className="text-xs" style={{ color: "var(--dim)" }}>No history yet.</p>
          ) : (
            <div className="flex flex-wrap gap-2">
              {historyQuery.data.slice(0, 10).map((entry) => (
                <div
                  key={entry.id}
                  className="flex items-center gap-1.5 rounded-lg px-2.5 py-1"
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
  onShare,
}: {
  pr: PRRecord;
  onShare?: (pr: PRRecord) => void;
}) {
  const scoreStr = formatScore(Number(pr.current_score), pr.unit);
  const unitLabel = UNIT_LABELS[pr.unit] ?? pr.unit;
  const dateStr = new Date(pr.beaten_on).toLocaleDateString(undefined, {
    month: "short", day: "numeric", year: "numeric",
  });

  return (
    <div
      className="relative overflow-hidden rounded-[1.5rem] px-5 py-4"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      <Particles prId={pr.id} />

      {onShare && (
        <button
          type="button"
          onClick={() => onShare(pr)}
          className="absolute top-3 right-3 rounded-lg px-2 py-1 text-[10px] font-semibold opacity-50 hover:opacity-90 transition-opacity"
          style={{ background: "var(--border)", color: "var(--dim)" }}
          title="Share PR"
        >
          🔗
        </button>
      )}

      <p className="text-sm font-semibold truncate pr-8" style={{ color: "var(--text)" }}>{pr.name}</p>
      <div className="mt-1.5 flex items-baseline gap-1.5">
        <span className="text-2xl font-bold tabular-nums" style={{ color: "var(--primary)" }}>{scoreStr}</span>
        <span className="text-xs font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{unitLabel}</span>
      </div>
      <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{dateStr}</p>
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
  const scoreStr = formatScore(Number(pr.current_score), pr.unit);
  const unitLabel = UNIT_LABELS[pr.unit] ?? pr.unit;
  const dateStr = new Date(pr.beaten_on).toLocaleDateString(undefined, {
    month: "short", day: "numeric", year: "numeric",
  });

  return (
    <div
      className="relative overflow-hidden rounded-[1.8rem] p-5 pb-14"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      <Particles prId={pr.id} />

      {/* Share — top right */}
      {onShare && (
        <button
          type="button"
          onClick={() => onShare(pr)}
          className="absolute top-4 right-4 rounded-xl px-3 py-1.5 text-sm font-semibold"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          title="Share PR"
        >
          Share 🔗
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
            {pr.higher_is_better ? "Higher is better" : "Lower is better"} · {dateStr}
          </p>
        </div>
      </PRHistoryTooltip>

      {/* Edit + Delete — bottom right, side-by-side */}
      {(onEdit || onDelete) && (
        <div className="absolute bottom-4 right-4 flex gap-2">
          {onEdit && (
            <button
              type="button"
              onClick={() => onEdit(pr)}
              className="rounded-xl w-9 h-9 flex items-center justify-center text-base"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
              title="Edit"
            >
              ✏️
            </button>
          )}
          {onDelete && (
            <button
              type="button"
              onClick={() => onDelete(pr)}
              className="rounded-xl w-9 h-9 flex items-center justify-center text-base"
              style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
              title="Delete"
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
  if (compact) return <CompactCard pr={pr} onShare={onShare} />;
  return <FullCard pr={pr} onEdit={onEdit} onDelete={onDelete} onShare={onShare} />;
}
