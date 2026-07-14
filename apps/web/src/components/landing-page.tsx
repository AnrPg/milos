"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { fetchExecution } from "@/api/executions";
import { PantheonSection } from "@/components/pantheon/PantheonSection";
import { ChallengeCard } from "@/components/workouts/ChallengeCard";
import {
  fetchLandingPayload,
  updateLeaderboardOptIn,
  type AdminMetrics,
  type LandingPayload,
  type LeaderboardEntry,
  type TrainingQuote,
} from "@/api/landing";
import { HelpIcon, InfoModal } from "@/components/InfoModal";
import { ReviewFormPanel } from "@/components/panels/ReviewFormPanel";
import { WellbeingFormPanel } from "@/components/panels/WellbeingFormPanel";
import { useSession } from "@/components/session-provider";

// ── Badge helpers ─────────────────────────────────────────────────────────────

const KNOWN_WORKOUT_TYPES = ["crossfit", "strength", "gymnastics", "aerobics", "flexibility", "recovery", "session"] as const;

type BadgeTier = "bronze" | "silver" | "gold" | "platinum" | "master";

function getBadgeTier(badgeKey: string): BadgeTier {
  if (badgeKey.endsWith("_mastery")) return "master";
  if (badgeKey.startsWith("workouts_")) {
    const n = parseInt(badgeKey.split("_")[1] ?? "0", 10);
    if (n >= 200) return "platinum";
    if (n >= 50) return "gold";
    if (n >= 10) return "silver";
    return "bronze";
  }
  if (badgeKey.startsWith("prs_")) {
    const n = parseInt(badgeKey.split("_")[1] ?? "0", 10);
    if (n >= 50) return "platinum";
    if (n >= 25) return "gold";
    if (n >= 5) return "silver";
    return "bronze";
  }
  if (badgeKey.startsWith("streak_")) {
    const n = parseInt(badgeKey.split("_")[1] ?? "0", 10);
    if (n >= 90) return "gold";
    if (n >= 30) return "silver";
    return "bronze";
  }
  return "bronze";
}

const TIER_ICON: Record<BadgeTier, string> = {
  bronze: "🥉",
  silver: "🥈",
  gold: "🥇",
  platinum: "💎",
  master: "⭐",
};

function getBadgeDescription(badgeKey: string): string {
  if (badgeKey.startsWith("workouts_")) {
    const n = badgeKey.split("_")[1];
    return `Completed ${n} workouts`;
  }
  if (badgeKey.startsWith("prs_")) {
    const n = badgeKey.split("_")[1];
    return `Logged ${n} personal records`;
  }
  if (badgeKey.startsWith("streak_")) {
    const n = badgeKey.split("_")[1];
    return `Maintained a ${n}-day training streak`;
  }
  if (badgeKey.endsWith("_mastery")) {
    const type = badgeKey.replace("_mastery", "").replace(/_/g, " ");
    return `Achieved mastery in ${type}`;
  }
  return "Training milestone achieved";
}


// ── Count-up animation hook ───────────────────────────────────────────────────

function useCountUp(target: number, durationMs = 1200): number {
  const [value, setValue] = useState(0);
  const rafRef = useRef<number | null>(null);
  const startTimeRef = useRef<number | null>(null);

  useEffect(() => {
    if (target === 0) { setValue(0); return; }

    startTimeRef.current = null;

    function easeOutQuart(t: number) {
      return 1 - Math.pow(1 - t, 4);
    }

    function step(ts: number) {
      if (!startTimeRef.current) startTimeRef.current = ts;
      const elapsed = ts - startTimeRef.current;
      const progress = Math.min(elapsed / durationMs, 1);
      setValue(Math.round(easeOutQuart(progress) * target));
      if (progress < 1) {
        rafRef.current = requestAnimationFrame(step);
      }
    }

    rafRef.current = requestAnimationFrame(step);
    return () => { if (rafRef.current != null) cancelAnimationFrame(rafRef.current); };
  }, [target, durationMs]);

  return value;
}

// ── Admin hero metrics ────────────────────────────────────────────────────────

function AdminHero({ metrics }: { metrics: AdminMetrics }) {
  const euros = (metrics.total_outstanding_cents / 100).toLocaleString("el-GR", {
    style: "currency",
    currency: "EUR",
    maximumFractionDigits: 0,
  });

  const chips = [
    { label: "Members", value: String(metrics.member_count), href: "/admin/members" },
    { label: "Outstanding", value: euros, href: "/admin/finance/operations", danger: metrics.total_outstanding_cents > 0 },
    { label: "Pending approvals", value: String(metrics.pending_referral_approvals), href: "/admin/finance/operations" },
    { label: "Classes today", value: String(metrics.classes_today), href: "/admin/class-schedule" },
  ];

  return (
    <section className="rounded-[2.6rem] p-8" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>Milos Training</p>
      <h1 className="mt-4 text-3xl font-semibold tracking-tight md:text-4xl" style={{ color: "var(--text)" }}>
        Today at a glance
      </h1>
      <div className="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
        {chips.map((chip) => (
          <Link
            key={chip.label}
            href={chip.href}
            className="flex flex-col rounded-[1.5rem] px-4 py-4 transition-transform hover:-translate-y-0.5"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
          >
            <span
              className="text-2xl font-semibold tracking-tight"
              style={{ color: chip.danger ? "var(--danger)" : "var(--text)" }}
            >
              {chip.value}
            </span>
            <span className="mt-1.5 text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
              {chip.label}
            </span>
          </Link>
        ))}
      </div>
    </section>
  );
}

// ── Off-days banner ───────────────────────────────────────────────────────────

function OffDaysBanner({ offDays, preferencesSet }: { offDays: number[]; preferencesSet: boolean }) {
  const [dismissed, setDismissed] = useState(false);
  const todayDow = new Date().getDay(); // 0=Sun..6=Sat

  if (dismissed) return null;

  if (!preferencesSet) {
    return (
      <div
        className="flex items-start justify-between gap-4 rounded-2xl px-5 py-4"
        style={{ background: "color-mix(in srgb, var(--warning) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--warning) 30%, transparent)" }}
      >
        <div>
          <p className="text-sm font-semibold" style={{ color: "var(--warning)" }}>
            ⚠️ Set your rest days for accurate metrics
          </p>
          <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>
            Your Consistency and Perseverance scores exclude your scheduled rest days — but we don&apos;t know which days those are yet.
          </p>
          <Link
            href="/profile#training-schedule"
            className="mt-2 inline-block text-sm font-semibold underline-offset-2 hover:underline"
            style={{ color: "var(--warning)" }}
          >
            Set your rest days in Profile →
          </Link>
        </div>
        <button
          type="button"
          onClick={() => setDismissed(true)}
          className="shrink-0 text-sm font-semibold"
          style={{ color: "var(--dim)" }}
        >
          Dismiss
        </button>
      </div>
    );
  }

  if (!offDays.includes(todayDow)) return null;

  return (
    <div
      className="flex items-center justify-between gap-4 rounded-2xl px-5 py-3"
      style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 30%, transparent)" }}
    >
      <p className="text-sm font-semibold" style={{ color: "var(--primary)" }}>
        Today is your scheduled rest day — recovery is part of the programme.
      </p>
      <button
        type="button"
        onClick={() => setDismissed(true)}
        className="shrink-0 text-sm font-semibold"
        style={{ color: "var(--dim)" }}
      >
        Dismiss
      </button>
    </div>
  );
}

// ── Member/Athlete hero ───────────────────────────────────────────────────────

function MemberHero({
  nickname,
  streak,
  advancementCount,
  badges,
  quote,
}: {
  nickname: string;
  streak: number;
  advancementCount: number;
  badges: LandingPayload["gamification"]["badges"];
  quote: TrainingQuote | null | undefined;
}) {
  const animatedStreak = useCountUp(streak);

  const tieredBadges = useMemo(
    () =>
      badges.map((b, i) => ({
        ...b,
        tier: getBadgeTier(b.badge_key),
        description: getBadgeDescription(b.badge_key),
        isNewest: i === 0,
      })),
    [badges],
  );

  const greeting = useState(() => {
    const h = new Date().getHours();
    const morning = [
      `Rise and grind, ${nickname}! (Or just rise. Grind is optional.)`,
      `The barbells missed you, ${nickname}.`,
      `Coffee first, PRs second, ${nickname}. You know the order.`,
      `The gym called. It said "where were you yesterday?", ${nickname}.`,
      `Early bird gets the gains, ${nickname}. You're already winning.`,
      `The sun is up. The weights are waiting. Let's go, ${nickname}.`,
    ];
    const afternoon = [
      `Afternoon slump? Not on your watch, ${nickname}.`,
      `Lunch was just pre-workout, ${nickname}. You know that, right?`,
      `Halfway through the day and still going strong, ${nickname}.`,
      `The afternoon belongs to those who show up, ${nickname}.`,
      `Peak performance hours, ${nickname}. Let's not waste them.`,
      `Your future self will thank you for this one, ${nickname}.`,
    ];
    const evening = [
      `One more workout between you and the couch, ${nickname}.`,
      `Train now, sleep like a champion later, ${nickname}.`,
      `The day isn't over until you move, ${nickname}.`,
      `Evening edition, ${nickname}. The weights are still warm.`,
      `The best time was this morning. The second best is now, ${nickname}.`,
      `Dedication looks good on you, ${nickname}.`,
    ];
    const night = [
      `A true champion, ${nickname}. Or an insomniac. Either way — let's go.`,
      `Everyone else is asleep, ${nickname}. This is your moment.`,
      `Night owl mode: activated, ${nickname}. The weights don't judge.`,
      `Can't sleep? Might as well get stronger, ${nickname}.`,
      `Midnight hustle, ${nickname}. Respect.`,
      `The iron never sleeps, ${nickname}. Neither do you, apparently.`,
    ];
    const pool =
      h >= 5 && h < 12 ? morning :
      h >= 12 && h < 18 ? afternoon :
      h >= 18 && h < 22 ? evening :
      night;
    return pool[Math.floor(Math.random() * pool.length)]!;
  })[0];

  return (
    <section className="rounded-[2.6rem] p-8" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>Milos Training</p>

      <style>{`
        @keyframes quote-border-glow {
          0%, 100% {
            border-color: color-mix(in srgb, var(--primary) 22%, transparent);
            box-shadow: 0 0 0 0 color-mix(in srgb, var(--primary) 0%, transparent);
          }
          50% {
            border-color: color-mix(in srgb, var(--primary) 65%, transparent);
            box-shadow: 0 0 18px 3px color-mix(in srgb, var(--primary) 15%, transparent);
          }
        }
      `}</style>

      {/* Welcome */}
      <p className="mt-3 text-sm font-semibold" style={{ color: "var(--muted)" }}>
        {greeting}
      </p>

      {/* Quote */}
      <blockquote
        className="mt-4 rounded-2xl px-5 py-4"
        style={{
          border: "1.5px solid color-mix(in srgb, var(--primary) 22%, transparent)",
          animation: "quote-border-glow 3s ease-in-out infinite",
        }}
      >
        <p
          className="text-3xl font-bold leading-snug tracking-tight md:text-4xl"
          style={{ color: "var(--primary)", fontStyle: "italic" }}
        >
          {quote?.body ?? `Your training is in motion.`}
        </p>
        {quote?.author ? (
          <footer className="mt-2 text-sm" style={{ color: "var(--dim)" }}>— {quote.author}</footer>
        ) : null}
      </blockquote>

      {/* Streak + advancement + badge chips row */}
      <div className="mt-6 flex flex-wrap items-center gap-3">
        {/* Day streak chip */}
        <div
          className="flex items-baseline gap-1.5 rounded-2xl px-4 py-2.5"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
        >
          <span className="text-3xl font-bold tabular-nums" style={{ color: "var(--warning)" }}>
            {animatedStreak}
          </span>
          <span className="text-sm font-semibold" style={{ color: "var(--dim)" }}>day streak</span>
        </div>

        {/* Advancement chip */}
        {advancementCount > 0 && (
          <div
            className="flex items-baseline gap-1.5 rounded-2xl px-4 py-2.5"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
          >
            <span className="text-3xl font-bold tabular-nums" style={{ color: "var(--success)" }}>
              {advancementCount}
            </span>
            <span className="text-sm font-semibold" style={{ color: "var(--dim)" }}>advancements</span>
          </div>
        )}

        {/* Badge milestone chips */}
        {tieredBadges.slice(0, 6).map((badge, idx) => (
          <div
            key={badge.id}
            title={badge.description}
            className="flex items-center gap-1.5 rounded-2xl px-3 py-2"
            style={{
              background: "var(--panel-muted)",
              border: badge.isNewest
                ? "1px solid color-mix(in srgb, var(--primary) 60%, transparent)"
                : "1px solid var(--border)",
              boxShadow: badge.isNewest
                ? "0 0 10px color-mix(in srgb, var(--primary) 25%, transparent)"
                : "none",
              animation: `fadeInUp 0.4s ease both`,
              animationDelay: `${idx * 80}ms`,
              cursor: "default",
            }}
          >
            <span className="text-base leading-none">{TIER_ICON[badge.tier]}</span>
            <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
              {badge.label}
            </span>
          </div>
        ))}

        {tieredBadges.length === 0 && (
          <p className="text-sm" style={{ color: "var(--dim)" }}>
            Complete your first workout to earn your first badge.
          </p>
        )}
      </div>
    </section>
  );
}

// ── Main component ────────────────────────────────────────────────────────────

export function LandingPage() {
  const { currentUser, rotate, tokens } = useSession();
  const [leaderboardMode, setLeaderboardMode] = useState<"weekly" | "monthly">("weekly");
  const [selectedExecutionId, setSelectedExecutionId] = useState<string | null>(null);
  const [activeInfoModal, setActiveInfoModal] = useState<string | null>(null);
  const [trainingReadinessOpen, setTrainingReadinessOpen] = useState(false);
  const [reviewPanelOpen, setReviewPanelOpen] = useState(false);
  const [historyView, setHistoryView] = useState<"grid" | "list">("grid");
  const [historyTypeFilter, setHistoryTypeFilter] = useState<string | null>(null);
  const [historyDateFilter, setHistoryDateFilter] = useState<"all" | "week" | "month">("all");
  const [historyDateFrom, setHistoryDateFrom] = useState<string>("");
  const [historyDateTo, setHistoryDateTo] = useState<string>("");
  const [showDateRangeModal, setShowDateRangeModal] = useState(false);
  const [modalDateFrom, setModalDateFrom] = useState<string>("");
  const [modalDateTo, setModalDateTo] = useState<string>(new Date().toISOString().slice(0, 10));
  const queryClient = useQueryClient();

  const landingQuery = useQuery({
    queryKey: ["landing"],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => {
      if (!tokens?.access_token) throw new Error("Authentication required.");
      return fetchLandingPayload(tokens.access_token);
    },
  });

  const toggleLeaderboard = useMutation({
    mutationFn: async (optedIn: boolean) => {
      if (!tokens?.access_token) throw new Error("Authentication required.");
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
        ? landing?.gamification?.leaderboard?.weekly ?? []
        : landing?.gamification?.leaderboard?.monthly ?? [],
    [landing?.gamification?.leaderboard?.monthly, landing?.gamification?.leaderboard?.weekly, leaderboardMode],
  );

  if (landingQuery.isPending) {
    return (
      <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
        <div className="mx-auto max-w-5xl rounded-[2.4rem] p-8" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>Milos Training</p>
          <h1 className="mt-4 text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "var(--text)" }}>
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
      <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
        <div className="mx-auto max-w-5xl rounded-[2.4rem] p-8" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>Milos Training</p>
          <h1 className="mt-4 text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "var(--text)" }}>
            Your training overview is unavailable.
          </h1>
          <p className="mt-4 max-w-2xl text-base leading-7" style={{ color: "var(--muted)" }}>{message}</p>
          <div className="mt-6 flex flex-wrap gap-3">
            <button
              className="rounded-2xl px-5 py-3 text-sm font-semibold"
              style={{ background: "var(--text)", color: "var(--bg)" }}
              onClick={() => void landingQuery.refetch()}
              type="button"
            >
              Retry
            </button>
            <button
              className="rounded-2xl px-5 py-3 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--border)", border: "1px solid var(--border-strong)", color: "var(--text-soft)" }}
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
    <>
      {/* keyframe for badge chip stagger */}
      <style>{`
        @keyframes fadeInUp {
          from { opacity: 0; transform: translateY(8px); }
          to   { opacity: 1; transform: translateY(0); }
        }
      `}</style>

      <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
        <div className="mx-auto max-w-6xl space-y-8">

          {/* ── Off-days banner (non-admin) ─────────────────────────────── */}
          {!isAdmin && (
            <OffDaysBanner
              offDays={landing.gamification.preferences?.off_days ?? []}
              preferencesSet={landing.gamification.preferences !== null && landing.gamification.preferences !== undefined}
            />
          )}

          {/* ── Hero ───────────────────────────────────────────────────────── */}
          {isAdmin && landing.admin_metrics ? (
            <AdminHero metrics={landing.admin_metrics} />
          ) : (
            <MemberHero
              nickname={currentUser?.nickname ?? ""}
              streak={stats?.current_streak ?? 0}
              advancementCount={stats?.advancement_count ?? 0}
              badges={landing.gamification.badges}
              quote={landing.quote}
            />
          )}

          {/* ── Stats strip (non-admin only) ────────────────────────────── */}
          {!isAdmin && stats && (
            <section className="grid gap-4 sm:grid-cols-3">
              <article className="rounded-[1.9rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
                <div className="flex items-center gap-2">
                  <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>Motivation</p>
                  <HelpIcon tooltip="Workout frequency vs weekly target — last 10 weeks" onClick={() => setActiveInfoModal("volume")} />
                </div>
                {isNaN(Math.round(stats.motivation_score ?? NaN)) ? (
                  <p className="mt-3 text-base font-semibold" style={{ color: "var(--dim)" }}>
                    {stats.total_workouts === 0
                      ? "No workouts yet"
                      : weeklyWorkoutTarget === 0
                        ? "Set a weekly target"
                        : "Calculating…"}
                  </p>
                ) : (
                  <p className="mt-3 text-3xl font-semibold tracking-tight" style={{ color: "var(--success)" }}>
                    {Math.round(stats.motivation_score)}%
                  </p>
                )}
                <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>Last 10 weeks vs target</p>
              </article>

              <article className="rounded-[1.9rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
                <div className="flex items-center gap-2">
                  <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>Perseverance</p>
                  <HelpIcon tooltip="How closely you followed prescribed exercises" onClick={() => setActiveInfoModal("volume")} />
                </div>
                {isNaN(Math.round(stats.perseverance_score ?? NaN)) ? (
                  <p className="mt-3 text-base font-semibold" style={{ color: "var(--dim)" }}>
                    {stats.total_workouts === 0 ? "No workouts yet" : "Calculating…"}
                  </p>
                ) : (
                  <p className="mt-3 text-3xl font-semibold tracking-tight" style={{ color: "var(--primary)" }}>
                    {Math.round(stats.perseverance_score)}%
                  </p>
                )}
                <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>Last 7 training days</p>
              </article>

              <article className="rounded-[1.9rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
                <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>Training Volume</p>
                <p className="mt-3 text-3xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>
                  {stats.total_workouts}
                </p>
                <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>
                  {stats.total_prs > 0 ? `${stats.total_prs} PRs · ` : ""}
                  best streak {stats.longest_streak} days
                </p>
              </article>
            </section>
          )}

          {/* ── Challenges + Leaderboard ────────────────────────────────── */}
          <section className="grid gap-6 xl:grid-cols-[1.15fr_0.85fr]">
            <article id="challenges" className="rounded-[2.2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
              <div className="flex items-center justify-between gap-4">
                <div>
                  <div className="flex items-center gap-2">
                    <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>Challenges</p>
                    <HelpIcon tooltip="What are challenges?" onClick={() => setActiveInfoModal("challenges")} />
                  </div>
                  <h2 className="mt-3 text-2xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>Seasonal momentum</h2>
                </div>
                {isAdmin ? (
                  <Link
                    className="rounded-full px-4 py-2 text-sm font-semibold"
                    style={{ background: "var(--border)", border: "1px solid var(--border-strong)", color: "var(--text-soft)" }}
                    href="/admin/challenges"
                  >
                    Create
                  </Link>
                ) : null}
              </div>
              <div className="mt-5 space-y-4">
                {landing.gamification.active_challenges.length === 0 ? (
                  <p className="rounded-2xl px-4 py-5 text-sm" style={{ background: "var(--panel-muted)", color: "var(--dim)" }}>
                    No active seasonal challenges yet.
                  </p>
                ) : (
                  landing.gamification.active_challenges.map((challenge) => (
                    <ChallengeCard key={challenge.id} challenge={challenge} />
                  ))
                )}
              </div>
            </article>

            <article className="rounded-[2.2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
              <div className="flex items-start justify-between gap-4">
                <div>
                  <div className="flex items-center gap-2">
                    <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>Leaderboard</p>
                    <HelpIcon tooltip="How does the leaderboard work?" onClick={() => setActiveInfoModal("leaderboard")} />
                  </div>
                  <h2 className="mt-3 text-2xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>Opt-in ranking</h2>
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
                    The leaderboard stays private until you explicitly opt in.
                  </p>
                  <button
                    className="mt-4 rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
                    style={{ background: "var(--text)", color: "var(--bg)" }}
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
                      <p className="rounded-2xl px-4 py-5 text-sm" style={{ background: "var(--panel-muted)", color: "var(--dim)" }}>
                        No ranked users yet for this period.
                      </p>
                    ) : (
                      leaderboardRows.map((entry) => (
                        <div
                          key={`${leaderboardMode}-${entry.user_id}`}
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
                                  ? `${entry.workouts_this_week} workouts this week`
                                  : `${entry.prs_this_month} PRs this month`}
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
                  {!isAdmin ? (
                    <button
                      className="mt-4 text-sm font-semibold underline-offset-4 hover:underline disabled:opacity-50"
                      style={{ color: "var(--dim)" }}
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

          {/* ── Hall of Fame / Pantheon (non-admin) ────────────────────── */}
          {!isAdmin && <PantheonSection />}

          {/* ── Coach notes (athlete only) ──────────────────────────────── */}
          {currentUser?.role === "athlete" ? (
            <section id="coach-notes" className="rounded-[2.2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
              <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>Coach notes</p>
              <h2 className="mt-3 text-2xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>Latest guidance</h2>
              <div className="mt-5 space-y-3">
                {landing.coach_notes.length === 0 ? (
                  <p className="rounded-2xl px-4 py-5 text-sm" style={{ background: "var(--panel-muted)", color: "var(--dim)" }}>
                    New coaching notes will appear here when your coach sends them.
                  </p>
                ) : (
                  landing.coach_notes.map((note) => (
                    <div key={note.id} className="rounded-[1.5rem] px-4 py-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                      <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>{note.body}</p>
                      <p className="mt-3 text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                        {new Date(note.inserted_at).toLocaleString()}
                      </p>
                    </div>
                  ))
                )}
              </div>
            </section>
          ) : null}

          {/* ── Workout history (non-admin) ─────────────────────────────── */}
          {!isAdmin && (() => {
            const now = new Date();
            const startOfWeek = new Date(now);
            startOfWeek.setDate(now.getDate() - now.getDay());
            startOfWeek.setHours(0, 0, 0, 0);
            const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);

            const hasCustomDateRange = historyDateFrom !== "" || historyDateTo !== "";
            const customFrom = historyDateFrom ? new Date(historyDateFrom) : null;
            const customTo = historyDateTo ? new Date(historyDateTo + "T23:59:59") : null;

            const datePresetHasData = (preset: "week" | "month") =>
              landing.recent_executions.some((ex) => {
                if (!ex.completed_at_utc) return false;
                const d = new Date(ex.completed_at_utc);
                if (preset === "week") return d >= startOfWeek;
                return d >= startOfMonth;
              });

            const filtered = landing.recent_executions.filter((ex) => {
              if (historyTypeFilter && (ex.workout_type ?? "session") !== historyTypeFilter) return false;
              if (ex.completed_at_utc) {
                const d = new Date(ex.completed_at_utc);
                if (hasCustomDateRange) {
                  if (customFrom && d < customFrom) return false;
                  if (customTo && d > customTo) return false;
                } else if (historyDateFilter !== "all") {
                  if (historyDateFilter === "week" && d < startOfWeek) return false;
                  if (historyDateFilter === "month" && d < startOfMonth) return false;
                }
              }
              return true;
            });

            const typeHasData = (t: string) =>
              landing.recent_executions.some((ex) => (ex.workout_type ?? "session") === t);

            return (
              <section className="rounded-[2.2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
                <div className="flex items-center justify-between gap-4 flex-wrap">
                  <div>
                    <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>Workout history</p>
                    <h2 className="mt-3 text-2xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>Recent completions</h2>
                  </div>
                  {/* View toggle */}
                  <div
                    className="flex rounded-xl overflow-hidden"
                    style={{ border: "1px solid var(--border)" }}
                  >
                    <button
                      type="button"
                      onClick={() => setHistoryView("grid")}
                      className="px-3 py-1.5 text-sm font-semibold"
                      style={{
                        background: historyView === "grid" ? "var(--primary)" : "var(--panel-muted)",
                        color: historyView === "grid" ? "var(--primary-contrast)" : "var(--muted)",
                      }}
                    >
                      ⊞
                    </button>
                    <button
                      type="button"
                      onClick={() => setHistoryView("list")}
                      className="px-3 py-1.5 text-sm font-semibold"
                      style={{
                        background: historyView === "list" ? "var(--primary)" : "var(--panel-muted)",
                        color: historyView === "list" ? "var(--primary-contrast)" : "var(--muted)",
                      }}
                    >
                      ≡
                    </button>
                  </div>
                </div>

                {/* Filters */}
                <div className="mt-4">
                  <div className="flex flex-wrap gap-2">
                    {/* Date preset chips */}
                    {(["all", "week", "month"] as const).map((d) => {
                      const hasData = d === "all" || datePresetHasData(d);
                      const isActive = !hasCustomDateRange && historyDateFilter === d;
                      return (
                        <button
                          key={d}
                          type="button"
                          disabled={!hasData}
                          onClick={() => { setHistoryDateFilter(d); setHistoryDateFrom(""); setHistoryDateTo(""); }}
                          title={!hasData ? "No workouts in this period" : undefined}
                          className="rounded-full px-3 py-1 text-xs font-semibold transition-opacity"
                          style={{
                            background: isActive ? "var(--primary)" : "var(--panel-muted)",
                            color: isActive ? "var(--primary-contrast)" : hasData ? "var(--muted)" : "var(--dim)",
                            border: isActive ? "1px solid var(--primary)" : "1px solid var(--border)",
                            opacity: hasData ? 1 : 0.45,
                            cursor: hasData ? "pointer" : "not-allowed",
                          }}
                        >
                          {d === "all" ? "All time" : d === "week" ? "This week" : "This month"}
                        </button>
                      );
                    })}

                    {/* Date range picker chip */}
                    <button
                      type="button"
                      onClick={() => {
                        setModalDateFrom(historyDateFrom);
                        setModalDateTo(historyDateTo || new Date().toISOString().slice(0, 10));
                        setShowDateRangeModal(true);
                      }}
                      className="rounded-full px-3 py-1 text-xs font-semibold"
                      style={{
                        background: hasCustomDateRange ? "var(--primary)" : "var(--panel-muted)",
                        color: hasCustomDateRange ? "var(--primary-contrast)" : "var(--muted)",
                        border: hasCustomDateRange ? "1px solid var(--primary)" : "1px solid var(--border)",
                      }}
                    >
                      {hasCustomDateRange
                        ? `${historyDateFrom || "…"} → ${historyDateTo || "…"}`
                        : "Pick date range"}
                    </button>

                    {hasCustomDateRange && (
                      <button
                        type="button"
                        onClick={() => { setHistoryDateFrom(""); setHistoryDateTo(""); setHistoryDateFilter("all"); }}
                        className="rounded-full px-3 py-1 text-xs font-semibold"
                        style={{ background: "var(--panel-muted)", color: "var(--dim)", border: "1px solid var(--border)" }}
                      >
                        ✕
                      </button>
                    )}

                    <div className="w-px self-stretch" style={{ background: "var(--border)" }} />

                    {/* Workout type chips */}
                    {KNOWN_WORKOUT_TYPES.map((t) => {
                      const hasData = typeHasData(t);
                      const isActive = historyTypeFilter === t;
                      return (
                        <button
                          key={t}
                          type="button"
                          disabled={!hasData}
                          onClick={() => setHistoryTypeFilter(isActive ? null : t)}
                          title={!hasData ? `No ${t.replace("_", " ")} workouts` : undefined}
                          className="rounded-full px-3 py-1 text-xs font-semibold capitalize transition-opacity"
                          style={{
                            background: isActive ? "var(--primary)" : "var(--panel-muted)",
                            color: isActive ? "var(--primary-contrast)" : hasData ? "var(--muted)" : "var(--dim)",
                            border: isActive ? "1px solid var(--primary)" : "1px solid var(--border)",
                            opacity: hasData ? 1 : 0.45,
                            cursor: hasData ? "pointer" : "not-allowed",
                          }}
                        >
                          {t.replace("_", " ")}
                        </button>
                      );
                    })}
                  </div>
                </div>

                {/* Date range modal */}
                {showDateRangeModal && (
                  <div
                    className="fixed inset-0 z-50 flex items-center justify-center p-4"
                    style={{ background: "rgba(0,0,0,0.45)" }}
                    onClick={() => setShowDateRangeModal(false)}
                  >
                    <div
                      className="w-full max-w-xs rounded-[1.8rem] p-6 space-y-4"
                      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
                      onClick={(e) => e.stopPropagation()}
                    >
                      <h3 className="text-base font-semibold" style={{ color: "var(--text)" }}>
                        Choose date range
                      </h3>
                      <div className="space-y-3">
                        <div className="space-y-1">
                          <label className="block text-xs font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
                            From (optional)
                          </label>
                          <input
                            type="date"
                            value={modalDateFrom}
                            onChange={(e) => setModalDateFrom(e.target.value)}
                            className="w-full rounded-xl px-3 py-2 text-sm outline-none"
                            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                          />
                        </div>
                        <div className="space-y-1">
                          <label className="block text-xs font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
                            To
                          </label>
                          <input
                            type="date"
                            value={modalDateTo}
                            onChange={(e) => setModalDateTo(e.target.value)}
                            className="w-full rounded-xl px-3 py-2 text-sm outline-none"
                            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                          />
                        </div>
                      </div>
                      <div className="flex gap-2 pt-1">
                        <button
                          type="button"
                          onClick={() => setShowDateRangeModal(false)}
                          className="rounded-xl px-4 py-2 text-sm font-semibold"
                          style={{ background: "var(--panel-muted)", color: "var(--muted)", border: "1px solid var(--border)" }}
                        >
                          Cancel
                        </button>
                        <button
                          type="button"
                          onClick={() => {
                            setHistoryDateFrom(modalDateFrom);
                            setHistoryDateTo(modalDateTo);
                            setHistoryDateFilter("all");
                            setShowDateRangeModal(false);
                          }}
                          className="flex-1 rounded-xl py-2 text-sm font-semibold"
                          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                        >
                          Apply
                        </button>
                      </div>
                    </div>
                  </div>
                )}

                {/* Cards */}
                <div className={`mt-5 ${historyView === "grid" ? "grid gap-3 md:grid-cols-2 xl:grid-cols-3" : "flex flex-col gap-2"}`}>
                  {filtered.length === 0 ? (
                    <p className="rounded-2xl px-4 py-5 text-sm" style={{ background: "var(--panel-muted)", color: "var(--dim)" }}>
                      {landing.recent_executions.length === 0
                        ? "Completed workouts will appear here once execution history starts building."
                        : "No workouts match these filters."}
                    </p>
                  ) : (
                    filtered.map((execution) => (
                      <button
                        key={execution.id}
                        className={`rounded-[1.5rem] text-left transition-transform hover:-translate-y-0.5 ${historyView === "list" ? "flex items-center gap-4 px-4 py-3" : "px-4 py-4"}`}
                        style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
                        onClick={() => setSelectedExecutionId(execution.id)}
                        type="button"
                      >
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-semibold truncate" style={{ color: "var(--text)" }}>
                            {execution.workout_title ?? "Workout"}
                          </p>
                          <p className="mt-1 text-xs uppercase tracking-[0.18em]" style={{ color: "var(--primary)" }}>
                            {(execution.workout_type ?? "session").replace("_", " ")}
                            {execution.scale_level_slug ? ` · ${execution.scale_level_slug}` : ""}
                          </p>
                        </div>
                        <div className={historyView === "list" ? "shrink-0 text-right" : "mt-3"}>
                          <p className="text-sm" style={{ color: "var(--muted)" }}>
                            {execution.completed_at_utc
                              ? new Date(execution.completed_at_utc).toLocaleDateString()
                              : "In progress"}
                          </p>
                          <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
                            {execution.exercise_notes.length} note{execution.exercise_notes.length === 1 ? "" : "s"} ·{" "}
                            {execution.section_scores.length} score{execution.section_scores.length === 1 ? "" : "s"}
                          </p>
                        </div>
                      </button>
                    ))
                  )}
                </div>
              </section>
            );
          })()}
        </div>

        {/* ── Info modals ──────────────────────────────────────────────── */}
        {activeInfoModal === "streak" ? (
          <InfoModal title="Current Streak" onClose={() => setActiveInfoModal(null)}>
            <p>
              <strong style={{ color: "var(--text)" }}>What it measures:</strong> The number of
              consecutive user-relative training weeks in which you completed at least {weeklyWorkoutTarget}{" "}
              workout{weeklyWorkoutTarget === 1 ? "" : "s"}.
            </p>
            <p>
              <strong style={{ color: "var(--text)" }}>How to improve:</strong> Complete at least{" "}
              {weeklyWorkoutTarget} workout{weeklyWorkoutTarget === 1 ? "" : "s"} each training week.
              A streak shield can protect one missed target week.
            </p>
            <p>
              <strong style={{ color: "var(--text)" }}>Why it matters:</strong> Streaks build the habit
              of regular weekly training volume.
            </p>
          </InfoModal>
        ) : null}

        {activeInfoModal === "leaderboard" ? (
          <InfoModal title="Leaderboard" onClose={() => setActiveInfoModal(null)}>
            <p>
              <strong style={{ color: "var(--text)" }}>What it measures:</strong> Your ranking among
              members who have opted in, based on workout volume and frequency.
            </p>
            <p>
              <strong style={{ color: "var(--text)" }}>Weekly ranking:</strong> Counts workouts completed
              in the current calendar week.
            </p>
            <p>
              <strong style={{ color: "var(--text)" }}>Monthly ranking:</strong> Counts personal records
              (PRs) logged in the current month.
            </p>
            <p>
              <strong style={{ color: "var(--text)" }}>Privacy:</strong> The leaderboard is opt-in only.
              Your data is never visible to others unless you explicitly join.
            </p>
          </InfoModal>
        ) : null}

        {activeInfoModal === "volume" ? (
          <InfoModal title="Consistency Score" onClose={() => setActiveInfoModal(null)}>
            <p>
              <strong style={{ color: "var(--text)" }}>What it measures:</strong> The percentage of weeks
              in the last 12 weeks in which you completed at least {weeklyWorkoutTarget} workout
              {weeklyWorkoutTarget === 1 ? "" : "s"}.
            </p>
            <p>
              <strong style={{ color: "var(--text)" }}>How to improve:</strong> Show up consistently —
              complete at least {weeklyWorkoutTarget} workout{weeklyWorkoutTarget === 1 ? "" : "s"} per
              week to count that week toward your score.
            </p>
            <p>
              <strong style={{ color: "var(--text)" }}>Why it matters:</strong> Consistency over time
              predicts long-term athletic progress better than any single metric.
            </p>
          </InfoModal>
        ) : null}

        {activeInfoModal === "challenges" ? (
          <InfoModal title="Seasonal Challenges" onClose={() => setActiveInfoModal(null)}>
            <p>
              <strong style={{ color: "var(--text)" }}>What they are:</strong> Time-limited goals set by
              your coach or the platform to keep your training purposeful and energised.
            </p>
            <p>
              <strong style={{ color: "var(--text)" }}>How to participate:</strong> Challenges start
              automatically when they go live — just complete the prescribed workouts and your
              progress updates in real time.
            </p>
            <p>
              <strong style={{ color: "var(--text)" }}>Rewards:</strong> Completing a challenge earns
              you a badge displayed on your profile milestones board.
            </p>
          </InfoModal>
        ) : null}

        {/* ── Execution detail modal ──────────────────────────────────── */}
        {selectedExecutionId ? (
          <div className="fixed inset-0 z-40 flex items-end justify-center p-4 md:items-center" style={{ background: "rgba(0,0,0,0.65)" }} role="presentation">
            <div
              className="max-h-[85vh] w-full max-w-2xl overflow-y-auto rounded-[2rem] p-6"
              style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
            >
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>Workout history</p>
                  <h3 className="mt-3 text-2xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>
                    {selectedExecution?.workout_title ?? "Loading..."}
                  </h3>
                </div>
                <button
                  className="rounded-full px-4 py-2 text-sm font-semibold"
                  style={{ background: "var(--border)", border: "1px solid var(--border-strong)", color: "var(--text-soft)" }}
                  onClick={() => setSelectedExecutionId(null)}
                  type="button"
                >
                  Close
                </button>
              </div>

              {selectedExecutionQuery.isPending ? (
                <p className="mt-6 text-sm" style={{ color: "var(--dim)" }}>Loading execution details...</p>
              ) : selectedExecution ? (
                <div className="mt-6 space-y-6">
                  <div className="grid gap-3 sm:grid-cols-3">
                    <div className="rounded-2xl px-4 py-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                      <p className="text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>Type</p>
                      <p className="mt-2 text-sm font-semibold" style={{ color: "var(--text)" }}>{selectedExecution.workout_type ?? "Unknown"}</p>
                    </div>
                    <div className="rounded-2xl px-4 py-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                      <p className="text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>Scale</p>
                      <p className="mt-2 text-sm font-semibold" style={{ color: "var(--text)" }}>{selectedExecution.scale_level_slug ?? "Base"}</p>
                    </div>
                    <div className="rounded-2xl px-4 py-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                      <p className="text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>Completed</p>
                      <p className="mt-2 text-sm font-semibold" style={{ color: "var(--text)" }}>
                        {selectedExecution.completed_at_utc ? new Date(selectedExecution.completed_at_utc).toLocaleString() : "In progress"}
                      </p>
                    </div>
                  </div>

                  <div>
                    <p className="text-sm font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>Section scores</p>
                    <div className="mt-3 space-y-2">
                      {selectedExecution.section_scores.length === 0 ? (
                        <p className="rounded-2xl px-4 py-4 text-sm" style={{ background: "var(--panel-muted)", color: "var(--dim)" }}>No scores were submitted.</p>
                      ) : (
                        selectedExecution.section_scores.map((score) => (
                          <div key={score.section_id} className="rounded-2xl px-4 py-3 text-sm" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--muted)" }}>
                            <span className="font-semibold" style={{ color: "var(--text)" }}>
                              {score.section_name ?? score.section_id}
                            </span>
                            : {String(score.value)} {score.unit ?? ""}
                          </div>
                        ))
                      )}
                    </div>
                  </div>

                  <div>
                    <p className="text-sm font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>Modifications and notes</p>
                    <div className="mt-3 space-y-3">
                      {selectedExecution.exercise_notes.length === 0 ? (
                        <p className="rounded-2xl px-4 py-4 text-sm" style={{ background: "var(--panel-muted)", color: "var(--dim)" }}>No exercise notes were submitted.</p>
                      ) : (
                        selectedExecution.exercise_notes.map((note) => (
                          <div
                            key={note.id ?? `${note.exercise_id}-${note.selected_text}`}
                            className="rounded px-3 py-2"
                            style={{ background: "color-mix(in srgb, var(--primary) 8%, transparent)", borderLeft: "4px solid color-mix(in srgb, var(--primary) 50%, transparent)" }}
                          >
                            <p className="text-sm font-medium" style={{ color: "var(--text)" }}>{note.selected_text}</p>
                            {note.note_text ? <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>{note.note_text}</p> : null}
                            {note.tags && note.tags.length > 0 ? (
                              <p className="mt-2 text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{note.tags.join(" · ")}</p>
                            ) : null}
                          </div>
                        ))
                      )}
                    </div>
                  </div>
                </div>
              ) : (
                <p className="mt-6 text-sm" style={{ color: "var(--primary-strong)" }}>
                  {selectedExecutionQuery.error instanceof Error ? selectedExecutionQuery.error.message : "Execution details could not be loaded."}
                </p>
              )}
            </div>
          </div>
        ) : null}

        {trainingReadinessOpen && (
          <WellbeingFormPanel onClose={() => setTrainingReadinessOpen(false)} />
        )}
        {reviewPanelOpen && (
          <ReviewFormPanel onClose={() => setReviewPanelOpen(false)} />
        )}
      </main>
    </>
  );
}
