"use client";



import {useUiTranslations} from "@/i18n/ui";
import { useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import { getPRHistory, type PRRecord, type PRUnit } from "@/api/gamification";
import { useSession } from "@/components/session-provider";

function formatScore(score: number, unit: PRUnit): string {
  if (unit === "mins_secs") {
    const total = Math.round(score);
    const m = String(Math.floor(total / 60)).padStart(2, "0");
    const s = String(total % 60).padStart(2, "0");
    return `${m}:${s}`;
  }
  return Number.isInteger(score) ? String(score) : score.toFixed(2);
}

export function PRHistoryModal({ pr, onClose }: { pr: PRRecord; onClose: () => void }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();

  const historyQuery = useQuery({
    queryKey: ["prs", pr.id, "history"],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => getPRHistory(tokens!.access_token, pr.id),
  });

  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", handleKey);
    return () => window.removeEventListener("keydown", handleKey);
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center p-4 sm:items-center"
      style={{ background: "rgba(0,0,0,0.5)" }}
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div
        className="w-full max-w-md rounded-[2rem] p-6"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        <div className="flex items-start justify-between gap-4">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{i18n("prHistoryf17c6df")}</p>
            <h2 className="mt-1 text-xl font-semibold" style={{ color: "var(--text)" }}>{pr.name}</h2>
          </div>
          <button type="button" onClick={onClose} className="text-xl font-light shrink-0" style={{ color: "var(--dim)" }}>✕</button>
        </div>

        <div className="mt-5 space-y-2">
          {historyQuery.isPending ? (
            <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
          ) : historyQuery.data?.length === 0 ? (
            <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("noHistoryRecordedYetebab110")}</p>
          ) : (
            historyQuery.data?.map((entry) => (
              <div
                key={entry.id}
                className="flex items-center justify-between rounded-xl px-4 py-3"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
              >
                <span className="text-sm font-semibold tabular-nums" style={{ color: "var(--primary)" }}>
                  {formatScore(Number(entry.score), pr.unit)} {pr.unit !== "mins_secs" ? pr.unit : ""}
                </span>
                <span className="text-xs" style={{ color: "var(--dim)" }}>
                  {new Date(entry.beaten_on).toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" })}
                </span>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
}
