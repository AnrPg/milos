"use client";





import {useUiTranslations} from "@/i18n/ui";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { fetchChallengeLeaderboard, optInChallenge, optOutChallenge } from "@/api/challenges";
import { useSession } from "@/components/session-provider";
import type { ChallengeRecord, LastProgressEvent } from "@/api/landing";

function progressEventText(event: LastProgressEvent): string {
  if (event.events.length === 1) {
    return `You gained +${event.total_points} pts ${event.events[0].label}`;
  }
  const breakdown = event.events.map((e) => `${e.label} (+${e.points})`).join(", ");
  return `+${event.total_points} pts this workout: ${breakdown}`;
}

function completionsRemainingText(challenge: ChallengeRecord): string {
  if (challenge.completed) return "Target reached!";
  const rem = challenge.completions_remaining;
  if (rem === 0) return "Almost there!";
  return `${rem} completion${rem === 1 ? "" : "s"} to go`;
}

export function ChallengeCard({ challenge }: { challenge: ChallengeRecord }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const [expanded, setExpanded] = useState(false);

  const leaderboardQuery = useQuery({
    queryKey: ["challenges", challenge.id, "leaderboard"],
    enabled: expanded && Boolean(tokens?.access_token) && challenge.is_opted_in,
    queryFn: () => {
      if (!tokens?.access_token) throw new Error(i18n("notAuthenticated0c91acb"));
      return fetchChallengeLeaderboard(tokens.access_token, challenge.id);
    },
  });

  const optInMutation = useMutation({
    mutationFn: async () => {
      if (!tokens?.access_token) throw new Error(i18n("notAuthenticated0c91acb"));
      return optInChallenge(tokens.access_token, challenge.id);
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["landing"] });
      void queryClient.invalidateQueries({
        queryKey: ["challenges", challenge.id, "leaderboard"],
      });
    },
  });

  const optOutMutation = useMutation({
    mutationFn: async () => {
      if (!tokens?.access_token) throw new Error(i18n("notAuthenticated0c91acb"));
      return optOutChallenge(tokens.access_token, challenge.id);
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["landing"] });
    },
  });

  const progressPct = Math.min(
    100,
    Math.round((challenge.progress / Math.max(challenge.target, 1)) * 100),
  );
  const pastTarget = challenge.progress > challenge.target;
  const isCustom = challenge.criteria_type === "custom";

  return (
    <article
      className="rounded-[1.6rem] p-4"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {challenge.title}
          </p>
          {challenge.description ? (
            <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
              {challenge.description}
            </p>
          ) : null}
        </div>
        <div className="flex shrink-0 items-center gap-2">
          {challenge.completed ? (
            <span
              className="rounded-full px-2 py-1 text-[10px] font-semibold uppercase tracking-wider"
              style={{
                background: "color-mix(in srgb, var(--success) 12%, transparent)",
                color: "var(--success)",
                border: "1px solid color-mix(in srgb, var(--success) 30%, transparent)",
              }}
            >
              {pastTarget && challenge.is_opted_in ? i18n("inHallOfFame048726d") : i18n("targetReacheddc27c47")}
            </span>
          ) : null}
          <span
            className="rounded-full px-2 py-1 text-[10px] font-semibold"
            style={{ background: "color-mix(in srgb, var(--primary) 12%, transparent)", color: "var(--primary)" }}
          >
            {challenge.badge_label}
          </span>
        </div>
      </div>

      <div className="mt-3 h-2 overflow-hidden rounded-full" style={{ background: "var(--border)" }}>
        <div
          className="h-full rounded-full transition-all"
          style={{
            width: (progressPct) + "%",
            background: challenge.completed ? "var(--success)" : "var(--primary)",
          }}
        />
      </div>

      <div
        className="mt-2 flex items-center justify-between text-xs"
        style={{ color: "var(--muted)" }}
      >
        <span>
          {challenge.progress}/{challenge.target}
          {isCustom ? i18n("pts4abdfc6") : ""}
          {pastTarget && challenge.is_opted_in
            ? "· " + (challenge.progress - challenge.target) + i18n("ptsBonus2c2dc1b")
            : ""}
        </span>
        <span style={{ color: challenge.completed ? "var(--success)" : "var(--muted)" }}>
          {isCustom ? completionsRemainingText(challenge) : null}
        </span>
      </div>

      {isCustom && challenge.last_progress_event ? (
        <p className="mt-2 text-xs font-medium" style={{ color: "var(--warning)" }}>
          {progressEventText(challenge.last_progress_event)}
        </p>
      ) : null}

      {isCustom ? (
        <div className="mt-3">
          <div className="flex items-center justify-between gap-2">
            <button
              type="button"
              className="rounded-full px-3 py-1 text-[11px] font-semibold transition-colors"
              style={
                challenge.is_opted_in
                  ? {
                      background: "color-mix(in srgb, var(--warning) 12%, transparent)",
                      color: "var(--warning)",
                      border: "1px solid color-mix(in srgb, var(--warning) 30%, transparent)",
                    }
                  : { background: "var(--border)", color: "var(--muted)" }
              }
              disabled={optInMutation.isPending || optOutMutation.isPending}
              onClick={() => {
                if (challenge.is_opted_in) {
                  void optOutMutation.mutateAsync();
                } else {
                  void optInMutation.mutateAsync();
                }
              }}
            >
              {challenge.is_opted_in ? i18n("leaveHallOfFame6c5f448") : i18n("joinHallOfFamed29b192")}
            </button>

            {challenge.is_opted_in ? (
              <button
                type="button"
                className="text-[11px]"
                style={{ color: "var(--dim)" }}
                onClick={() => setExpanded((v) => !v)}
              >
                {expanded ? i18n("hide6c29ab8") : i18n("hallOfFame695c438")}
              </button>
            ) : null}
          </div>

          {expanded && challenge.is_opted_in ? (
            <div className="mt-3">
              <p
                className="mb-2 text-[11px] font-semibold uppercase tracking-[0.16em]"
                style={{ color: "var(--dim)" }}
              >
                {i18n("hallOfFame6203a65")}
              </p>
              {leaderboardQuery.isPending ? (
                <p className="text-xs" style={{ color: "var(--dim)" }}>
                  {i18n("loading33ce417")}
                </p>
              ) : leaderboardQuery.data?.participants.length === 0 ? (
                <p className="text-xs" style={{ color: "var(--dim)" }}>
                  {i18n("noEntriesYetBeTheFirsta56781b")}
                </p>
              ) : (
                <div className="space-y-1">
                  {leaderboardQuery.data?.participants.map((entry) => {
                    const isMine =
                      entry.rank === leaderboardQuery.data?.my_rank &&
                      entry.progress === leaderboardQuery.data?.my_progress;
                    const barPct = Math.min(
                      100,
                      Math.round((entry.progress / Math.max(entry.target, 1)) * 100),
                    );

                    return (
                      <div
                        key={entry.user_id}
                        className="flex items-center gap-2 rounded-xl px-3 py-2"
                        style={
                          isMine
                            ? {
                                background: "color-mix(in srgb, var(--warning) 8%, transparent)",
                                border: "1px solid color-mix(in srgb, var(--warning) 20%, transparent)",
                              }
                            : { background: "var(--panel)" }
                        }
                      >
                        <span
                          className="w-5 shrink-0 text-[11px] font-bold"
                          style={{ color: "var(--dim)" }}
                        >
                          {entry.rank}
                        </span>
                        <div className="min-w-0 flex-1">
                          <div className="flex items-center justify-between gap-2">
                            <span
                              className="truncate text-xs font-medium"
                              style={{ color: isMine ? "var(--warning)" : "var(--text)" }}
                            >
                              {entry.nickname ?? i18n("athleteaa86fd2")}
                              {isMine ? "(you)" : ""}
                            </span>
                            <span className="shrink-0 text-[11px]" style={{ color: "var(--muted)" }}>
                              {entry.progress} {i18n("pts4abdfc6")}
                            </span>
                          </div>
                          <div
                            className="mt-1 h-1 overflow-hidden rounded-full"
                            style={{ background: "var(--border)" }}
                          >
                            <div
                              className="h-full rounded-full"
                              style={{
                                width: (barPct) + "%",
                                background: entry.completed_at ? "var(--success)" : "var(--primary)",
                              }}
                            />
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          ) : null}
        </div>
      ) : null}
    </article>
  );
}
