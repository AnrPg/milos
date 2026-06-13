"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { fetchExecution } from "@/api/executions";
import { ChallengeCard } from "@/components/workouts/ChallengeCard";
import {
  fetchLandingPayload,
  updateLeaderboardOptIn,
  type LandingPayload,
  type LeaderboardEntry,
} from "@/api/landing";
import { HelpIcon, InfoModal } from "@/components/InfoModal";
import { NotificationBell } from "@/components/notifications/NotificationBell";
import { useSession } from "@/components/session-provider";

export function LandingPage() {
  const { currentUser, rotate, signOut, tokens } = useSession();
  const [leaderboardMode, setLeaderboardMode] = useState<"weekly" | "monthly">("weekly");
  const [selectedExecutionId, setSelectedExecutionId] = useState<string | null>(null);
  const [activeInfoModal, setActiveInfoModal] = useState<string | null>(null);
  const queryClient = useQueryClient();

  const landingQuery = useQuery({
    queryKey: ["landing"],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => {
      if (!tokens?.access_token) {
        throw new Error("Authentication required.");
      }

      return fetchLandingPayload(tokens.access_token);
    },
  });

  const toggleLeaderboard = useMutation({
    mutationFn: async (optedIn: boolean) => {
      if (!tokens?.access_token) {
        throw new Error("Authentication required.");
      }

      return updateLeaderboardOptIn(tokens.access_token, optedIn);
    },
    onSuccess: (result) => {
      queryClient.setQueryData<LandingPayload>(["landing"], (current) =>
        current
          ? {
              ...current,
              gamification: {
                  ...current.gamification,
                  leaderboard: {
                    ...current.gamification.leaderboard,
                    opted_in: result.opted_in,
                    visible: result.visible,
                    weekly: result.weekly,
                    monthly: result.monthly,
                  },
              },
            }
          : current,
      );
    },
  });

  const selectedExecutionQuery = useQuery({
    queryKey: ["execution", selectedExecutionId],
    enabled: Boolean(tokens?.access_token && selectedExecutionId),
    queryFn: async () => {
      if (!tokens?.access_token || !selectedExecutionId) {
        throw new Error("Execution not available.");
      }

      return fetchExecution(tokens.access_token, selectedExecutionId);
    },
  });

  const landing = landingQuery.data;
  const leaderboardRows = useMemo<LeaderboardEntry[]>(
    () =>
      leaderboardMode === "weekly"
        ? landing?.gamification.leaderboard.weekly ?? []
        : landing?.gamification.leaderboard.monthly ?? [],
    [landing?.gamification.leaderboard.monthly, landing?.gamification.leaderboard.weekly, leaderboardMode],
  );

  if (landingQuery.isPending) {
    return (
      <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "#0A0A0F" }}>
        <div className="mx-auto max-w-5xl rounded-[2.4rem] p-8" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
          <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "#d95d39" }}>Landing</p>
          <h1 className="mt-4 text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "#F0EDF8" }}>
            Loading your training overview...
          </h1>
        </div>
      </main>
    );
  }

  if (landingQuery.isError || !landing) {
    const message =
      landingQuery.error instanceof Error
        ? landingQuery.error.message
        : "The landing page could not be loaded.";

    return (
      <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "#0A0A0F" }}>
        <div className="mx-auto max-w-5xl rounded-[2.4rem] p-8" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
          <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "#d95d39" }}>Landing</p>
          <h1 className="mt-4 text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "#F0EDF8" }}>
            Your training overview is unavailable.
          </h1>
          <p className="mt-4 max-w-2xl text-base leading-7" style={{ color: "#8888aa" }}>{message}</p>
          <div className="mt-6 flex flex-wrap gap-3">
            <button
              className="rounded-2xl px-5 py-3 text-sm font-semibold"
              style={{ background: "#F0EDF8", color: "#0A0A0F" }}
              onClick={() => void landingQuery.refetch()}
              type="button"
            >
              Retry
            </button>
            <button
              className="rounded-2xl px-5 py-3 text-sm font-semibold disabled:opacity-50"
              style={{ background: "#1a1a28", border: "1px solid #2a2a3a", color: "#c0c0d8" }}
              disabled={!tokens}
              onClick={() => void rotate()}
              type="button"
            >
              Refresh session
            </button>
          </div>
        </div>
      </main>
    );
  }

  const stats = landing.gamification.stats;
  const weeklyWorkoutTarget = landing.gamification.settings.weekly_workout_target;
  const isAdmin = currentUser?.role === "admin";
  const selectedExecution = selectedExecutionQuery.data;
  const leaderboardVisible = landing.gamification.leaderboard.visible;

  return (
    <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "#0A0A0F" }}>
      <div className="mx-auto max-w-6xl space-y-8">
        <section className="rounded-[2.6rem] p-8" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
          <div className="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <div className="flex items-center gap-3">
                <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "#d95d39" }}>Milos Training</p>
                <NotificationBell />
              </div>
              <h1 className="mt-4 text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "#F0EDF8" }}>
                {currentUser?.nickname}, your training week is in motion.
              </h1>
              <p className="mt-4 max-w-2xl text-base leading-7" style={{ color: "#8888aa" }}>
                Streaks, PRs, seasonal challenges, and recent execution history are now surfaced here as the
                day-to-day training read model.
              </p>
            </div>

            <div className="grid gap-3 sm:grid-cols-2">
              {isAdmin ? (
                <>
                  <Link
                    className="rounded-2xl px-5 py-3 text-center text-sm font-semibold"
                    style={{ background: "#F0EDF8", color: "#0A0A0F" }}
                    href="/admin"
                  >
                    Open admin
                  </Link>
                  <Link
                    className="rounded-2xl px-5 py-3 text-center text-sm font-semibold"
                    style={{ background: "#1a1a28", border: "1px solid #2a2a3a", color: "#c0c0d8" }}
                    href="/admin/challenges"
                  >
                    Manage challenges
                  </Link>
                </>
              ) : (
                <Link
                  className="rounded-2xl px-5 py-3 text-center text-sm font-semibold"
                  style={{ background: "#F0EDF8", color: "#0A0A0F" }}
                  href={currentUser?.role === "athlete" ? "/my-workouts" : "/schedule"}
                >
                  {currentUser?.role === "athlete" ? "Open my workouts" : "Browse schedule"}
                </Link>
              )}

              <button
                className="rounded-2xl px-5 py-3 text-sm font-semibold disabled:opacity-50"
                style={{ background: "#1a1a28", border: "1px solid #2a2a3a", color: "#c0c0d8" }}
                disabled={!tokens}
                onClick={() => void rotate()}
                type="button"
              >
                Refresh session
              </button>
              <button
                className="rounded-2xl px-5 py-3 text-sm font-semibold"
                style={{ background: "rgba(217,93,57,0.1)", border: "1px solid rgba(217,93,57,0.2)", color: "#d95d39" }}
                onClick={signOut}
                type="button"
              >
                Log out
              </button>
            </div>
          </div>
        </section>

        <section className="grid gap-4 md:grid-cols-4">
          <article className="rounded-[1.9rem] p-5" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
            <div className="flex items-center gap-2">
              <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "#55556a" }}>Current streak</p>
              <HelpIcon tooltip="What is a streak?" onClick={() => setActiveInfoModal("streak")} />
            </div>
            <p className="mt-3 text-3xl font-semibold tracking-tight" style={{ color: "#d9ab4e" }}>{stats.current_streak} wk</p>
            <p className="mt-2 text-sm" style={{ color: "#8888aa" }}>{stats.current_streak_shields} shield ready</p>
          </article>

          <article className="rounded-[1.9rem] p-5" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
            <div className="flex items-center gap-2">
              <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "#55556a" }}>Consistency</p>
              <HelpIcon tooltip="What is consistency score?" onClick={() => setActiveInfoModal("volume")} />
            </div>
            <p className="mt-3 text-3xl font-semibold tracking-tight" style={{ color: "#4db89c" }}>{Math.round(stats.consistency_score)}%</p>
            <p className="mt-2 text-sm" style={{ color: "#8888aa" }}>Last 12 weeks</p>
          </article>

          <article className="rounded-[1.9rem] p-5" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
            <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "#55556a" }}>Total workouts</p>
            <p className="mt-3 text-3xl font-semibold tracking-tight" style={{ color: "#F0EDF8" }}>{stats.total_workouts}</p>
            <p className="mt-2 text-sm" style={{ color: "#8888aa" }}>Longest streak {stats.longest_streak}</p>
          </article>

          <article className="rounded-[1.9rem] p-5" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
            <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "#55556a" }}>Total PRs</p>
            <p className="mt-3 text-3xl font-semibold tracking-tight" style={{ color: "#F0EDF8" }}>{stats.total_prs}</p>
            <p className="mt-2 text-sm" style={{ color: "#8888aa" }}>{stats.last_workout_at ? `Last done ${new Date(stats.last_workout_at).toLocaleDateString()}` : "No completed workout yet"}</p>
          </article>
        </section>

        <section className="grid gap-6 xl:grid-cols-[1.15fr_0.85fr]">
          <article id="challenges" className="rounded-[2.2rem] p-6" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
            <div className="flex items-center justify-between gap-4">
              <div>
                <div className="flex items-center gap-2">
                  <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "#55556a" }}>Challenges</p>
                  <HelpIcon tooltip="What are challenges?" onClick={() => setActiveInfoModal("challenges")} />
                </div>
                <h2 className="mt-3 text-2xl font-semibold tracking-tight" style={{ color: "#F0EDF8" }}>Seasonal momentum</h2>
              </div>
              {isAdmin ? (
                <Link
                  className="rounded-full px-4 py-2 text-sm font-semibold"
                  style={{ background: "#1a1a28", border: "1px solid #2a2a3a", color: "#c0c0d8" }}
                  href="/admin/challenges"
                >
                  Create
                </Link>
              ) : null}
            </div>

            <div className="mt-5 space-y-4">
              {landing.gamification.active_challenges.length === 0 ? (
                <p className="rounded-2xl px-4 py-5 text-sm" style={{ background: "#0d0d18", color: "#55556a" }}>
                  No active seasonal challenges yet.
                </p>
              ) : (
                landing.gamification.active_challenges.map((challenge) => (
                  <ChallengeCard key={challenge.id} challenge={challenge} />
                ))
              )}
            </div>
          </article>

          <article className="rounded-[2.2rem] p-6" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
            <div className="flex items-start justify-between gap-4">
              <div>
                <div className="flex items-center gap-2">
                  <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "#55556a" }}>Leaderboard</p>
                  <HelpIcon tooltip="How does the leaderboard work?" onClick={() => setActiveInfoModal("leaderboard")} />
                </div>
                <h2 className="mt-3 text-2xl font-semibold tracking-tight" style={{ color: "#F0EDF8" }}>Opt-in ranking</h2>
              </div>
              <div className="flex rounded-full p-1" style={{ background: "#1a1a28" }}>
                {(["weekly", "monthly"] as const).map((mode) => (
                  <button
                    key={mode}
                    className="rounded-full px-3 py-1 text-xs font-semibold capitalize"
                    onClick={() => setLeaderboardMode(mode)}
                    style={{
                      background: leaderboardMode === mode ? "#F0EDF8" : "transparent",
                      color: leaderboardMode === mode ? "#0A0A0F" : "#55556a",
                    }}
                    type="button"
                  >
                    {mode}
                  </button>
                ))}
              </div>
            </div>

            {!leaderboardVisible ? (
              <div className="mt-6 rounded-[1.8rem] p-5" style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}>
                <p className="text-sm font-medium" style={{ color: "#8888aa" }}>
                  The leaderboard stays private until you explicitly opt in.
                </p>
                <button
                  className="mt-4 rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
                  style={{ background: "#F0EDF8", color: "#0A0A0F" }}
                  disabled={toggleLeaderboard.isPending}
                  onClick={() => void toggleLeaderboard.mutateAsync(true)}
                  type="button"
                >
                  Join leaderboard
                </button>
              </div>
            ) : (
              <>
                <div className="mt-5 space-y-3">
                  {leaderboardRows.length === 0 ? (
                    <p className="rounded-2xl px-4 py-5 text-sm" style={{ background: "#0d0d18", color: "#55556a" }}>
                      No ranked users yet for this period.
                    </p>
                  ) : (
                    leaderboardRows.map((entry) => (
                      <div
                        key={`${leaderboardMode}-${entry.user_id}`}
                        className="flex items-center justify-between rounded-2xl px-4 py-3"
                        style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}
                      >
                        <div className="flex items-center gap-3">
                          <span
                            className="flex h-8 w-8 items-center justify-center rounded-full text-sm font-semibold"
                            style={{ background: "#1a1a28", color: "#c0c0d8" }}
                          >
                            {entry.rank}
                          </span>
                          <div>
                            <p className="text-sm font-semibold" style={{ color: "#F0EDF8" }}>{entry.nickname}</p>
                            <p className="text-xs" style={{ color: "#55556a" }}>
                              {leaderboardMode === "weekly" ? `${entry.workouts_this_week} workouts this week` : `${entry.prs_this_month} PRs this month`}
                            </p>
                          </div>
                        </div>
                        <span className="text-sm font-semibold" style={{ color: "#c97b4b" }}>
                          {leaderboardMode === "weekly" ? entry.workouts_this_week : entry.prs_this_month}
                        </span>
                      </div>
                    ))
                  )}
                </div>

                {!isAdmin ? (
                  <button
                    className="mt-4 text-sm font-semibold underline-offset-4 hover:underline disabled:opacity-50"
                    style={{ color: "#55556a" }}
                    disabled={toggleLeaderboard.isPending}
                    onClick={() => void toggleLeaderboard.mutateAsync(false)}
                    type="button"
                  >
                    Leave leaderboard
                  </button>
                ) : null}
              </>
            )}
          </article>
        </section>

        <section className="grid gap-6 xl:grid-cols-[1fr_0.8fr]">
          <article className="rounded-[2.2rem] p-6" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
            <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "#55556a" }}>Badges</p>
            <h2 className="mt-3 text-2xl font-semibold tracking-tight" style={{ color: "#F0EDF8" }}>Milestones earned</h2>
            <div className="mt-5 grid gap-3 sm:grid-cols-2">
              {landing.gamification.badges.length === 0 ? (
                <p className="rounded-2xl px-4 py-5 text-sm" style={{ background: "#0d0d18", color: "#55556a" }}>
                  Finish your first scored sessions to start filling the board.
                </p>
              ) : (
                landing.gamification.badges.map((badge) => (
                  <div key={badge.id} className="rounded-[1.5rem] px-4 py-4" style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}>
                    <p className="text-sm font-semibold" style={{ color: "#F0EDF8" }}>{badge.label}</p>
                    <p className="mt-1 text-xs uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                      {new Date(badge.earned_at).toLocaleDateString()}
                    </p>
                  </div>
                ))
              )}
            </div>
          </article>

          {landing.membership ? (
            <article className="rounded-[2.2rem] p-6" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
              <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "#55556a" }}>Membership</p>
              <h2 className="mt-3 text-2xl font-semibold tracking-tight" style={{ color: "#F0EDF8" }}>Status snapshot</h2>
              <dl className="mt-5 space-y-3 text-sm" style={{ color: "#8888aa" }}>
                <div className="flex items-center justify-between gap-4">
                  <dt>Package</dt>
                  <dd style={{ color: "#F0EDF8" }}>{landing.membership.package_name ?? "Not assigned"}</dd>
                </div>
                <div className="flex items-center justify-between gap-4">
                  <dt>Entitlement</dt>
                  <dd style={{ color: "#F0EDF8" }}>{landing.membership.entitlement_status ?? "Inactive"}</dd>
                </div>
                <div className="flex items-center justify-between gap-4">
                  <dt>Expiration</dt>
                  <dd style={{ color: "#F0EDF8" }}>{landing.membership.expiration_date ?? "Not set"}</dd>
                </div>
                <div className="flex items-center justify-between gap-4">
                  <dt>Last paid</dt>
                  <dd style={{ color: "#F0EDF8" }}>{landing.membership.last_paid ?? "Not set"}</dd>
                </div>
                <div className="flex items-center justify-between gap-4">
                  <dt>Amount</dt>
                  <dd style={{ color: "#F0EDF8" }}>
                    {landing.membership.amount == null
                      ? "Not set"
                      : new Intl.NumberFormat("en-GB", {
                          style: "currency",
                          currency: landing.membership.currency ?? "EUR",
                        }).format(landing.membership.amount / 100)}
                  </dd>
                </div>
              </dl>
            </article>
          ) : null}

          {currentUser?.role === "athlete" ? (
            <article id="coach-notes" className="rounded-[2.2rem] p-6" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
              <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "#55556a" }}>Coach notes</p>
              <h2 className="mt-3 text-2xl font-semibold tracking-tight" style={{ color: "#F0EDF8" }}>Latest guidance</h2>
              <div className="mt-5 space-y-3">
                {landing.coach_notes.length === 0 ? (
                  <p className="rounded-2xl px-4 py-5 text-sm" style={{ background: "#0d0d18", color: "#55556a" }}>
                    New coaching notes will appear here when your coach sends them.
                  </p>
                ) : (
                  landing.coach_notes.map((note) => (
                    <div key={note.id} className="rounded-[1.5rem] px-4 py-4" style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}>
                      <p className="text-sm leading-6" style={{ color: "#c0c0d8" }}>{note.body}</p>
                      <p className="mt-3 text-xs uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>
                        {new Date(note.inserted_at).toLocaleString()}
                      </p>
                    </div>
                  ))
                )}
              </div>
            </article>
          ) : null}
        </section>

        <section className="rounded-[2.2rem] p-6" style={{ background: "#111118", border: "1px solid #1a1a28" }}>
          <div className="flex items-center justify-between gap-4">
            <div>
              <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "#55556a" }}>Workout history</p>
              <h2 className="mt-3 text-2xl font-semibold tracking-tight" style={{ color: "#F0EDF8" }}>Recent completions</h2>
            </div>
          </div>

          <div className="mt-5 grid gap-3 md:grid-cols-2 xl:grid-cols-3">
            {landing.recent_executions.length === 0 ? (
              <p className="rounded-2xl px-4 py-5 text-sm" style={{ background: "#0d0d18", color: "#55556a" }}>
                Completed workouts will appear here once execution history starts building.
              </p>
            ) : (
              landing.recent_executions.map((execution) => (
                <button
                  key={execution.id}
                  className="rounded-[1.5rem] px-4 py-4 text-left transition-transform hover:-translate-y-0.5"
                  style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}
                  onClick={() => setSelectedExecutionId(execution.id)}
                  type="button"
                >
                  <p className="text-sm font-semibold" style={{ color: "#F0EDF8" }}>
                    {execution.workout_title ?? "Workout"}
                  </p>
                  <p className="mt-1 text-xs uppercase tracking-[0.18em]" style={{ color: "#d95d39" }}>
                    {(execution.workout_type ?? "session").replace("_", " ")}
                    {execution.scale_level_slug ? ` · ${execution.scale_level_slug}` : ""}
                  </p>
                  <p className="mt-3 text-sm" style={{ color: "#8888aa" }}>
                    {execution.completed_at_utc
                      ? new Date(execution.completed_at_utc).toLocaleString()
                      : "In progress"}
                  </p>
                  <p className="mt-2 text-xs" style={{ color: "#55556a" }}>
                    {execution.exercise_notes.length} note{execution.exercise_notes.length === 1 ? "" : "s"} ·{" "}
                    {execution.section_scores.length} score
                    {execution.section_scores.length === 1 ? "" : "s"}
                  </p>
                </button>
              ))
            )}
          </div>
        </section>
      </div>

      {activeInfoModal === "streak" ? (
        <InfoModal title="Current Streak" onClose={() => setActiveInfoModal(null)}>
          <p>
            <strong style={{ color: "#F0EDF8" }}>What it measures:</strong> The number of
            consecutive user-relative training weeks in which you completed at least {weeklyWorkoutTarget}{" "}
            workout{weeklyWorkoutTarget === 1 ? "" : "s"}.
          </p>
          <p>
            <strong style={{ color: "#F0EDF8" }}>How to improve:</strong> Complete at least{" "}
            {weeklyWorkoutTarget} workout{weeklyWorkoutTarget === 1 ? "" : "s"} each training week.
            A streak shield can protect one missed target week.
          </p>
          <p>
            <strong style={{ color: "#F0EDF8" }}>Why it matters:</strong> Streaks build the habit
            of regular weekly training volume.
          </p>
        </InfoModal>
      ) : null}

      {activeInfoModal === "leaderboard" ? (
        <InfoModal title="Leaderboard" onClose={() => setActiveInfoModal(null)}>
          <p>
            <strong style={{ color: "#F0EDF8" }}>What it measures:</strong> Your ranking among
            members who have opted in, based on workout volume and frequency.
          </p>
          <p>
            <strong style={{ color: "#F0EDF8" }}>Weekly ranking:</strong> Counts workouts completed
            in the current calendar week.
          </p>
          <p>
            <strong style={{ color: "#F0EDF8" }}>Monthly ranking:</strong> Counts personal records
            (PRs) logged in the current month.
          </p>
          <p>
            <strong style={{ color: "#F0EDF8" }}>Privacy:</strong> The leaderboard is opt-in only.
            Your data is never visible to others unless you explicitly join.
          </p>
        </InfoModal>
      ) : null}

      {activeInfoModal === "volume" ? (
        <InfoModal title="Consistency Score" onClose={() => setActiveInfoModal(null)}>
          <p>
            <strong style={{ color: "#F0EDF8" }}>What it measures:</strong> The percentage of weeks
            in the last 12 weeks in which you completed at least {weeklyWorkoutTarget} workout
            {weeklyWorkoutTarget === 1 ? "" : "s"}.
          </p>
          <p>
            <strong style={{ color: "#F0EDF8" }}>How to improve:</strong> Show up consistently —
            complete at least {weeklyWorkoutTarget} workout{weeklyWorkoutTarget === 1 ? "" : "s"} per
            week to count that week toward your score.
          </p>
          <p>
            <strong style={{ color: "#F0EDF8" }}>Why it matters:</strong> Consistency over time
            predicts long-term athletic progress better than any single metric.
          </p>
        </InfoModal>
      ) : null}

      {activeInfoModal === "challenges" ? (
        <InfoModal title="Seasonal Challenges" onClose={() => setActiveInfoModal(null)}>
          <p>
            <strong style={{ color: "#F0EDF8" }}>What they are:</strong> Time-limited goals set by
            your coach or the platform to keep your training purposeful and energised.
          </p>
          <p>
            <strong style={{ color: "#F0EDF8" }}>How to participate:</strong> Challenges start
            automatically when they go live — just complete the prescribed workouts and your
            progress updates in real time.
          </p>
          <p>
            <strong style={{ color: "#F0EDF8" }}>Rewards:</strong> Completing a challenge earns
            you a badge displayed on your profile milestones board.
          </p>
        </InfoModal>
      ) : null}

      {selectedExecutionId ? (
        <div className="fixed inset-0 z-40 flex items-end justify-center p-4 md:items-center" style={{ background: "rgba(0,0,0,0.65)" }} role="presentation">
          <div
            className="max-h-[85vh] w-full max-w-2xl overflow-y-auto rounded-[2rem] p-6"
            style={{ background: "#111118", border: "1px solid #1a1a28" }}
          >
            <div className="flex items-start justify-between gap-4">
              <div>
                <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "#55556a" }}>Workout history</p>
                <h3 className="mt-3 text-2xl font-semibold tracking-tight" style={{ color: "#F0EDF8" }}>
                  {selectedExecution?.workout_title ?? "Loading..."}
                </h3>
              </div>
              <button
                className="rounded-full px-4 py-2 text-sm font-semibold"
                style={{ background: "#1a1a28", border: "1px solid #2a2a3a", color: "#c0c0d8" }}
                onClick={() => setSelectedExecutionId(null)}
                type="button"
              >
                Close
              </button>
            </div>

            {selectedExecutionQuery.isPending ? (
              <p className="mt-6 text-sm" style={{ color: "#55556a" }}>Loading execution details...</p>
            ) : selectedExecution ? (
              <div className="mt-6 space-y-6">
                <div className="grid gap-3 sm:grid-cols-3">
                  <div className="rounded-2xl px-4 py-3" style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}>
                    <p className="text-xs uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>Type</p>
                    <p className="mt-2 text-sm font-semibold" style={{ color: "#F0EDF8" }}>{selectedExecution.workout_type ?? "Unknown"}</p>
                  </div>
                  <div className="rounded-2xl px-4 py-3" style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}>
                    <p className="text-xs uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>Scale</p>
                    <p className="mt-2 text-sm font-semibold" style={{ color: "#F0EDF8" }}>{selectedExecution.scale_level_slug ?? "Base"}</p>
                  </div>
                  <div className="rounded-2xl px-4 py-3" style={{ background: "#0d0d18", border: "1px solid #1a1a28" }}>
                    <p className="text-xs uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>Completed</p>
                    <p className="mt-2 text-sm font-semibold" style={{ color: "#F0EDF8" }}>
                      {selectedExecution.completed_at_utc ? new Date(selectedExecution.completed_at_utc).toLocaleString() : "In progress"}
                    </p>
                  </div>
                </div>

                <div>
                  <p className="text-sm font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>Section scores</p>
                  <div className="mt-3 space-y-2">
                    {selectedExecution.section_scores.length === 0 ? (
                      <p className="rounded-2xl px-4 py-4 text-sm" style={{ background: "#0d0d18", color: "#55556a" }}>No scores were submitted.</p>
                    ) : (
                      selectedExecution.section_scores.map((score) => (
                        <div key={score.section_id} className="rounded-2xl px-4 py-3 text-sm" style={{ background: "#0d0d18", border: "1px solid #1a1a28", color: "#8888aa" }}>
                          <span className="font-semibold" style={{ color: "#F0EDF8" }}>
                            {score.section_name ?? score.section_id}
                          </span>
                          : {String(score.value)} {score.unit ?? ""}
                        </div>
                      ))
                    )}
                  </div>
                </div>

                <div>
                  <p className="text-sm font-semibold uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>Modifications and notes</p>
                  <div className="mt-3 space-y-3">
                    {selectedExecution.exercise_notes.length === 0 ? (
                      <p className="rounded-2xl px-4 py-4 text-sm" style={{ background: "#0d0d18", color: "#55556a" }}>No exercise notes were submitted.</p>
                    ) : (
                      selectedExecution.exercise_notes.map((note) => (
                        <div
                          key={note.id ?? `${note.exercise_id}-${note.selected_text}`}
                          className="rounded px-3 py-2"
                          style={{ background: "rgba(217,93,57,0.08)", borderLeft: "4px solid rgba(217,93,57,0.5)" }}
                        >
                          <p className="text-sm font-medium" style={{ color: "#F0EDF8" }}>{note.selected_text}</p>
                          {note.note_text ? <p className="mt-1 text-sm" style={{ color: "#8888aa" }}>{note.note_text}</p> : null}
                          {note.tags && note.tags.length > 0 ? (
                            <p className="mt-2 text-xs uppercase tracking-[0.18em]" style={{ color: "#55556a" }}>{note.tags.join(" · ")}</p>
                          ) : null}
                        </div>
                      ))
                    )}
                  </div>
                </div>
              </div>
            ) : (
              <p className="mt-6 text-sm" style={{ color: "#e07a5f" }}>
                {selectedExecutionQuery.error instanceof Error ? selectedExecutionQuery.error.message : "Execution details could not be loaded."}
              </p>
            )}
          </div>
        </div>
      ) : null}
    </main>
  );
}
