"use client";

import { useMemo, useState } from "react";

import type { LandingPayload, LeaderboardEntry } from "@/api/landing";
import { HelpIcon, InfoModal } from "@/components/InfoModal";
import { useLeaderboardOptIn } from "@/components/member-app/progress/use-landing";
import { useUiTranslations } from "@/i18n/ui";

/**
 * The gym's opt-in leaderboard (weekly workouts, monthly PRs). It stays a
 * full card so the slot never moves (brief §4.2); members who have not opted
 * in see the opt-in prompt in its place.
 */
export function LeaderboardCard({ leaderboard }: { leaderboard: LandingPayload["gamification"]["leaderboard"] }) {
  const i18n = useUiTranslations();
  const [leaderboardMode, setLeaderboardMode] = useState<"weekly" | "monthly">("weekly");
  const [activeInfoModal, setActiveInfoModal] = useState<"leaderboard" | null>(null);
  const leaderboardVisible = leaderboard.visible;
  const leaderboardOptedIn = leaderboard.opted_in;
  const leaderboardRows = useMemo<LeaderboardEntry[]>(
    () => (leaderboardMode === "weekly" ? leaderboard.weekly ?? [] : leaderboard.monthly ?? []),
    [leaderboard.weekly, leaderboard.monthly, leaderboardMode],
  );

  const toggleLeaderboard = useLeaderboardOptIn();

  return (
    <section className="rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <div className="flex items-start justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>{i18n("leaderboard0381247")}</p>
            <HelpIcon tooltip={i18n("howDoesTheLeaderboardWork74f2b8a")} onClick={() => setActiveInfoModal("leaderboard")} />
          </div>
          <h2 className="mt-3 text-2xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>{i18n("optInRanking04c1cd3")}</h2>
        </div>
        <div className="flex rounded-full p-1" style={{ background: "var(--border)" }}>
          {(["weekly", "monthly"] as const).map((mode) => (
            <button
              key={mode}
              className="rounded-full px-3 py-1 text-xs font-semibold capitalize"
              onClick={() => setLeaderboardMode(mode)}
              style={{
                background: leaderboardMode === mode ? "var(--text)" : "transparent",
                color: leaderboardMode === mode ? "var(--bg)" : "var(--dim)",
              }}
              type="button"
            >
              {mode}
            </button>
          ))}
        </div>
      </div>

      {!leaderboardVisible ? (
        <div className="mt-6 rounded-[1.8rem] p-5" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
          <p className="text-sm font-medium" style={{ color: "var(--muted)" }}>
            {leaderboardOptedIn
              ? i18n("theLeaderboardIsCurrentlyUnavailableYourOptIn96132c6")
              : i18n("theLeaderboardStaysPrivateUntilYouExplicitlyOpt9e982f1")}
          </p>
          {!leaderboardOptedIn ? <button
            className="mt-4 rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
            style={{ background: "var(--text)", color: "var(--bg)" }}
            disabled={toggleLeaderboard.isPending}
            onClick={() => void toggleLeaderboard.mutateAsync(true)}
            type="button"
          >
            {i18n("joinLeaderboardad480b1")}
          </button> : null}
        </div>
      ) : (
        <>
          <div className="mt-5 space-y-3">
            {leaderboardRows.length === 0 ? (
              <p className="rounded-2xl px-4 py-5 text-sm" style={{ background: "var(--panel-muted)", color: "var(--dim)" }}>
                {i18n("noRankedUsersYetForThisPeriod2fa66a4")}
              </p>
            ) : (
              leaderboardRows.map((entry) => (
                <div
                  key={(leaderboardMode) + "-" + (entry.user_id)}
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
                        {leaderboardMode === "weekly"
                          ? (entry.workouts_this_week) + i18n("workoutsThisWeek0268fc5")
                          : (entry.prs_this_month) + i18n("prsThisMonthd85bc56")}
                      </p>
                    </div>
                  </div>
                  <span className="text-sm font-semibold" style={{ color: "var(--primary)" }}>
                    {leaderboardMode === "weekly" ? entry.workouts_this_week : entry.prs_this_month}
                  </span>
                </div>
              ))
            )}
          </div>
          <button
            className="mt-4 text-sm font-semibold underline-offset-4 hover:underline disabled:opacity-50"
            style={{ color: "var(--dim)" }}
            disabled={toggleLeaderboard.isPending}
            onClick={() => void toggleLeaderboard.mutateAsync(false)}
            type="button"
          >
            {i18n("leaveLeaderboard834f047")}
          </button>
        </>
      )}
      {activeInfoModal === "leaderboard" ? (
        <InfoModal title={i18n("leaderboard0381247")} onClose={() => setActiveInfoModal(null)}>
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
