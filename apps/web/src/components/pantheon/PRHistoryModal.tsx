"use client";



import {useUiTranslations} from "@/i18n/ui";
import {useUiLocale} from "@/i18n/use-ui-locale";
import { useEffect } from "react";
import { useQuery } from "@tanstack/react-query";
import { getPRHistory, type PRRecord, type PRSupportingMetrics, type PRUnit } from "@/api/gamification";
import { useSession } from "@/components/session-provider";
import { SemanticLabel } from "@/components/semantic-label";

function formatScore(score: number, unit: PRUnit): string {
  if (unit === "mins_secs") {
    const total = Math.round(score);
    const m = String(Math.floor(total / 60)).padStart(2, "0");
    const s = String(total % 60).padStart(2, "0");
    return `${m}:${s}`;
  }
  return Number.isInteger(score) ? String(score) : score.toFixed(2);
}

function formatSupportingMetrics(metrics: PRSupportingMetrics, i18n: ReturnType<typeof useUiTranslations>) {
  const labels: Record<keyof PRSupportingMetrics, string> = {
    reps: i18n("reps702045f"),
    sets: i18n("sets2ab262f"),
    load_kg: `${i18n("semanticLoad")} (${i18n("kg1389845")})`,
    duration_seconds: `${i18n("time6c82e6d")} (${i18n("semanticSeconds")})`,
    distance_m: i18n("meters6ad427c"),
    calories: i18n("semanticKilocalories"),
    rounds: i18n("roundsceeac4a"),
    variation: i18n("variation15920a4"),
  };

  return (Object.entries(metrics) as [keyof PRSupportingMetrics, string | number][])
    .map(([key, value]) => `${labels[key]}: ${value}`)
    .join(" · ");
}

export function PRHistoryModal({ pr, onClose }: { pr: PRRecord; onClose: () => void }) {
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const { tokens } = useSession();

  const historyQuery = useQuery({
    queryKey: ["prs", pr.id, "history"],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => getPRHistory(tokens!.access_token, pr.id),
  });

  const entries = [
    {
      id: `current-${pr.id}`,
      score: pr.current_score,
      beaten_on: pr.beaten_on,
      supporting_metrics: pr.supporting_metrics,
      notes: pr.notes,
    },
    ...(historyQuery.data ?? []),
  ];

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
          ) : (
            entries.map((entry) => (
              <div
                key={entry.id}
                className="rounded-xl px-4 py-3"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
              >
                <div className="flex items-center justify-between gap-3">
                  <span className="text-sm font-semibold tabular-nums" style={{ color: "var(--primary)" }}>
                    {formatScore(Number(entry.score), pr.unit)} {pr.unit !== "mins_secs" ? <SemanticLabel value={pr.unit} /> : ""}
                  </span>
                  <span className="text-xs" style={{ color: "var(--dim)" }}>
                    {new Date(entry.beaten_on).toLocaleDateString(uiLocale, { month: "short", day: "numeric", year: "numeric" })}
                  </span>
                </div>
                {Object.keys(entry.supporting_metrics ?? {}).length > 0 && (
                  <p className="mt-1.5 text-xs" style={{ color: "var(--text-soft)" }}>
                    {formatSupportingMetrics(entry.supporting_metrics, i18n)}
                  </p>
                )}
                {entry.notes && (
                  <p className="mt-1.5 text-xs" style={{ color: "var(--dim)" }}>{entry.notes}</p>
                )}
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
}
