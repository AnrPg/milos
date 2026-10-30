"use client";

import { useState } from "react";

import type { LandingPayload, LeaderboardEntry } from "@/api/landing";
import { HelpIcon, InfoModal } from "@/components/InfoModal";
import { useUiTranslations } from "@/i18n/ui";

type Mode = "weekly" | "monthly";
const MODES: Mode[] = ["weekly", "monthly"];

/**
 * The gym's opt-in leaderboard (weekly workouts, monthly PRs). Comparison is
 * opt-in (vision §4.4) and joining or leaving lives in Εγώ › Κοινοποίηση &
 * ορατότητα, so the card shows only a visible ranking with rows; otherwise
 * it is hidden, not an empty state (§4.2). A period without rows is not
 * offered.
 */
export function LeaderboardCard({ leaderboard }: { leaderboard: LandingPayload["gamification"]["leaderboard"] }) {
  const i18n = useUiTranslations();
  const [picked, setPicked] = useState<Mode | null>(null);
  const [infoOpen, setInfoOpen] = useState(false);
  const rowsFor = (mode: Mode): LeaderboardEntry[] => (mode === "weekly" ? leaderboard.weekly : leaderboard.monthly) ?? [];
  const modes = leaderboard.visible ? MODES.filter((mode) => rowsFor(mode).length > 0) : [];
  if (modes.length === 0) return null;

  const mode = picked && modes.includes(picked) ? picked : modes[0];
  const rows = rowsFor(mode);

  return (
    <section className="rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <div className="flex items-start justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>{i18n("leaderboard0381247")}</p>
            <HelpIcon tooltip={i18n("howDoesTheLeaderboardWork74f2b8a")} onClick={() => setInfoOpen(true)} />
          </div>
          <h2 className="mt-3 text-2xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>{i18n("optInRanking04c1cd3")}</h2>
        </div>
        {modes.length > 1 ? (
          <div className="flex rounded-full p-1" style={{ background: "var(--border)" }}>
            {modes.map((value) => (
              <button
                key={value}
                className="rounded-full px-3 py-1 text-xs font-semibold capitalize"
                onClick={() => setPicked(value)}
                style={{
                  background: mode === value ? "var(--text)" : "transparent",
                  color: mode === value ? "var(--bg)" : "var(--dim)",
                }}
                type="button"
              >
                {value}
              </button>
            ))}
          </div>
        ) : null}
      </div>

      <div className="mt-5 space-y-3">
        {rows.map((entry) => (
          <div
            key={mode + "-" + entry.user_id}
            className="flex items-center justify-between rounded-2xl px-4 py-3"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
          >
            <div className="flex items-center gap-3">
              <span
                className="flex h-8 w-8 items-center justify-center rounded-full text-sm font-semibold"
                style={{ background: "var(--border)", color: "var(--text-soft)" }}
              >
                {entry.rank}
              </span>
              <div>
                <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{entry.nickname}</p>
                <p className="text-xs" style={{ color: "var(--dim)" }}>
                  {mode === "weekly"
                    ? i18n("workoutsThisWeekCount", { count: entry.workouts_this_week })
                    : i18n("prsThisMonthCount", { count: entry.prs_this_month })}
                </p>
              </div>
            </div>
            <span className="text-sm font-semibold" style={{ color: "var(--primary)" }}>
              {mode === "weekly" ? entry.workouts_this_week : entry.prs_this_month}
            </span>
          </div>
        ))}
      </div>
      {infoOpen ? (
        <InfoModal title={i18n("leaderboard0381247")} onClose={() => setInfoOpen(false)}>
          <p>
            <strong style={{ color: "var(--text)" }}>{i18n("whatItMeasuresbbab752")}</strong> {i18n("yourRankingAmongMembersWhoHaveOptedIn1b6e973")}
          </p>
          <p>
            <strong style={{ color: "var(--text)" }}>{i18n("weeklyRanking7015bcf")}</strong> {i18n("countsWorkoutsCompletedInTheCurrentCalendarWeek042a854")}
          </p>
          <p>
            <strong style={{ color: "var(--text)" }}>{i18n("monthlyRanking5999a91")}</strong> {i18n("countsPersonalRecordsPrsLoggedInTheCurrentf701a4e")}
          </p>
          <p>
            <strong style={{ color: "var(--text)" }}>{i18n("privacya512a08")}</strong> {i18n("theLeaderboardIsOptInOnlyYourData3e23cde")}
          </p>
        </InfoModal>
      ) : null}
    </section>
  );
}
