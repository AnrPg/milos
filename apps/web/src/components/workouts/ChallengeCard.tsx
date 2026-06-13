"use client";

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
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const [expanded, setExpanded] = useState(false);

  const leaderboardQuery = useQuery({
    queryKey: ["challenges", challenge.id, "leaderboard"],
    enabled: expanded && Boolean(tokens?.access_token) && challenge.is_opted_in,
    queryFn: () => {
      if (!tokens?.access_token) throw new Error("Not authenticated");
      return fetchChallengeLeaderboard(tokens.access_token, challenge.id);
    },
  });

  const optInMutation = useMutation({
    mutationFn: async () => {
      if (!tokens?.access_token) throw new Error("Not authenticated");
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
      if (!tokens?.access_token) throw new Error("Not authenticated");
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
      style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}
    >
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <p className="text-sm font-semibold" style={{ color: "#F0EDF8" }}>
            {challenge.title}
          </p>
          {challenge.description ? (
            <p className="mt-1 text-xs" style={{ color: "#55556a" }}>
              {challenge.description}
            </p>
          ) : null}
        </div>
        <div className="flex shrink-0 items-center gap-2">
          {challenge.completed ? (
            <span
              className="rounded-full px-2 py-1 text-[10px] font-semibold uppercase tracking-wider"
              style={{
                background: "rgba(34,197,94,0.12)",
                color: "#4ade80",
                border: "1px solid rgba(34,197,94,0.3)",
              }}
            >
              {pastTarget && challenge.is_opted_in ? "🏆 In Hall of Fame" : "Target reached!"}
            </span>
          ) : null}
          <span
            className="rounded-full px-2 py-1 text-[10px] font-semibold"
            style={{ background: "rgba(217,93,57,0.12)", color: "#d95d39" }}
          >
            {challenge.badge_label}
          </span>
        </div>
      </div>

      <div className="mt-3 h-2 overflow-hidden rounded-full" style={{ background: "#1a1a28" }}>
        <div
          className="h-full rounded-full transition-all"
          style={{
            width: `${progressPct}%`,
            background: challenge.completed ? "#4ade80" : "#d95d39",
          }}
        />
      </div>

      <div
        className="mt-2 flex items-center justify-between text-xs"
        style={{ color: "#8888aa" }}
      >
        <span>
          {challenge.progress}/{challenge.target}
          {isCustom ? " pts" : ""}
          {pastTarget && challenge.is_opted_in
            ? ` · ${challenge.progress - challenge.target} pts bonus`
            : ""}
        </span>
        <span style={{ color: challenge.completed ? "#4ade80" : "#8888aa" }}>
          {isCustom ? completionsRemainingText(challenge) : null}
        </span>
      </div>

      {isCustom && challenge.last_progress_event ? (
        <p className="mt-2 text-xs font-medium" style={{ color: "#fbbf24" }}>
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
                      background: "rgba(251,191,36,0.12)",
                      color: "#fbbf24",
                      border: "1px solid rgba(251,191,36,0.3)",
                    }
                  : { background: "#1a1a28", color: "#8888aa" }
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
              {challenge.is_opted_in ? "Leave Hall of Fame" : "Join Hall of Fame"}
            </button>

            {challenge.is_opted_in ? (
              <button
                type="button"
                className="text-[11px]"
                style={{ color: "#55556a" }}
                onClick={() => setExpanded((v) => !v)}
              >
                {expanded ? "▲ Hide" : "▼ Hall of Fame"}
              </button>
            ) : null}
          </div>

          {expanded && challenge.is_opted_in ? (
            <div className="mt-3">
              <p
                className="mb-2 text-[11px] font-semibold uppercase tracking-[0.16em]"
                style={{ color: "#55556a" }}
              >
                🏆 Hall of Fame
              </p>
              {leaderboardQuery.isPending ? (
                <p className="text-xs" style={{ color: "#55556a" }}>
                  Loading…
                </p>
              ) : leaderboardQuery.data?.participants.length === 0 ? (
                <p className="text-xs" style={{ color: "#55556a" }}>
                  No entries yet — be the first!
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
                                background: "rgba(251,191,36,0.08)",
                                border: "1px solid rgba(251,191,36,0.2)",
                              }
                            : { background: "#111118" }
                        }
                      >
                        <span
                          className="w-5 shrink-0 text-[11px] font-bold"
                          style={{ color: "#55556a" }}
                        >
                          {entry.rank}
                        </span>
                        <div className="min-w-0 flex-1">
                          <div className="flex items-center justify-between gap-2">
                            <span
                              className="truncate text-xs font-medium"
                              style={{ color: isMine ? "#fbbf24" : "#F0EDF8" }}
                            >
                              {entry.nickname ?? "Athlete"}
                              {isMine ? " (you)" : ""}
                            </span>
                            <span className="shrink-0 text-[11px]" style={{ color: "#8888aa" }}>
                              {entry.progress} pts
                            </span>
                          </div>
                          <div
                            className="mt-1 h-1 overflow-hidden rounded-full"
                            style={{ background: "#1a1a28" }}
                          >
                            <div
                              className="h-full rounded-full"
                              style={{
                                width: `${barPct}%`,
                                background: entry.completed_at ? "#4ade80" : "#d95d39",
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
