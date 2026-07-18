"use client";






import {useUiTranslations} from "@/i18n/ui";
import { localizeError, semanticLabel } from "@/i18n/presentation";
import {useUiLocale} from "@/i18n/use-ui-locale";
import { useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { fetchExecution } from "@/api/executions";
import { fetchAssignedWorkoutWeek } from "@/api/assigned-workouts";
import { fetchSchedule } from "@/api/schedule";
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
import { HomeDisclosure } from "@/components/home/HomeDisclosure";
import { ReviewFormPanel } from "@/components/panels/ReviewFormPanel";
import { WellbeingFormPanel } from "@/components/panels/WellbeingFormPanel";
import { useSession } from "@/components/session-provider";
import { SemanticLabel } from "@/components/semantic-label";
import { LocalizedScore } from "@/components/localized-score";
import { formatLocalIsoDate } from "@/components/schedule/calendar-window";
import { workoutCta } from "@/components/workout-cta";

// ── Badge helpers ─────────────────────────────────────────────────────────────

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


// ── Count-up animation hook ───────────────────────────────────────────────────

function useCountUp(target: number, durationMs = 1200): number {
  const [value, setValue] = useState(0);
  const rafRef = useRef<number | null>(null);
  const startTimeRef = useRef<number | null>(null);

  useEffect(() => {
    if (target === 0) {
      queueMicrotask(() => setValue(0));
      return;
    }

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
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
  const euros = (metrics.total_outstanding_cents / 100).toLocaleString(uiLocale, {
    style: "currency",
    currency: "EUR",
    maximumFractionDigits: 0,
  });

  const chips = [
    { label: i18n("members1cb449c"), value: String(metrics.member_count), href: "/admin/members" },
    { label: i18n("outstandingf8ee57e"), value: euros, href: "/admin/finance/operations", danger: metrics.total_outstanding_cents > 0 },
    { label: i18n("pendingApprovals6ac383a"), value: String(metrics.pending_referral_approvals), href: "/admin/finance/operations" },
    { label: i18n("classesTodayd01b776"), value: String(metrics.classes_today), href: "/admin/class-schedule" },
  ];

  return (
    <section className="rounded-[2.6rem] p-8" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>{i18n("milosTraining5b1a1c1")}</p>
      <h1 className="mt-4 text-3xl font-semibold tracking-tight md:text-4xl" style={{ color: "var(--text)" }}>
        {i18n("todayAtAGlance07e2821")}
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
  const i18n = useUiTranslations();
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
            {i18n("setYourRestDaysForAccurateMetrics6a7d46c")}
          </p>
          <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>
            {i18n("yourConsistencyAndPerseveranceScoresExcludeYourSchedulede6962c7")}
          </p>
          <Link
            href="/profile#training-schedule"
            className="mt-2 inline-block text-sm font-semibold underline-offset-2 hover:underline"
            style={{ color: "var(--warning)" }}
          >
            {i18n("setYourRestDaysInProfilefd0fbe4")}
          </Link>
        </div>
        <button
          type="button"
          onClick={() => setDismissed(true)}
          className="shrink-0 text-sm font-semibold"
          style={{ color: "var(--dim)" }}
        >
          {i18n("dismiss70afe9e")}
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
        {i18n("todayIsYourScheduledRestDayRecoveryIse1d7a10")}
      </p>
      <button
        type="button"
        onClick={() => setDismissed(true)}
        className="shrink-0 text-sm font-semibold"
        style={{ color: "var(--dim)" }}
      >
        {i18n("dismiss70afe9e")}
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
  const i18n = useUiTranslations();

  function getBadgeDescription(badgeKey: string): string {
    if (badgeKey.startsWith("workouts_")) {
      const n = badgeKey.split("_")[1];
      return i18n("completedValue0Workoutsde3ccd4", {value0: n});
    }
    if (badgeKey.startsWith("prs_")) {
      const n = badgeKey.split("_")[1];
      return i18n("loggedValue0PersonalRecords6eb75e4", {value0: n});
    }
    if (badgeKey.startsWith("streak_")) {
      const n = badgeKey.split("_")[1];
      return i18n("maintainedAValue0DayTrainingStreak0dbf33c", {value0: n});
    }
    if (badgeKey.endsWith("_mastery")) {
      const type = semanticLabel(badgeKey.replace("_mastery", ""), i18n);
      return i18n("achievedMasteryInValue01e7e1ec", {value0: type});
    }
    return i18n("trainingMilestoneAchieved56dc32b");
  }

  const animatedStreak = useCountUp(streak);

  const tieredBadges = badges.map((b, i) => ({
    ...b,
    tier: getBadgeTier(b.badge_key),
    description: getBadgeDescription(b.badge_key),
    isNewest: i === 0,
  }));

  const greeting = useState(() => {
    const h = new Date().getHours();
    const morning = [
      i18n("riseAndGrind3033458") + (nickname) + i18n("orJustRiseGrindIsOptional8d8c3f6"),
      i18n("theBarbellsMissedYoub43c56d") + (nickname) + ".",
      i18n("coffeeFirstPrsSecond69f0009") + (nickname) + i18n("youKnowTheOrderaa2bad9"),
      i18n("theGymCalledItSaidWhereWereYouef08f7d") + (nickname) + ".",
      i18n("earlyBirdGetsTheGains77f123b") + (nickname) + i18n("youReAlreadyWinninge6c3cef"),
      i18n("theSunIsUpTheWeightsAreWaiting171ab2a") + (nickname) + ".",
    ];
    const afternoon = [
      i18n("afternoonSlumpNotOnYourWatchb7a458d") + (nickname) + ".",
      i18n("lunchWasJustPreWorkout0bddce3") + (nickname) + i18n("youKnowThatRightf5b4ce7"),
      i18n("halfwayThroughTheDayAndStillGoingStronge7ef8ba") + (nickname) + ".",
      i18n("theAfternoonBelongsToThoseWhoShowUpfa22611") + (nickname) + ".",
      i18n("peakPerformanceHoursadbdea7") + (nickname) + i18n("letSNotWasteThem2bbfea8"),
      i18n("yourFutureSelfWillThankYouForThisb9d7f03") + (nickname) + ".",
    ];
    const evening = [
      i18n("oneMoreWorkoutBetweenYouAndTheCouch785f7b7") + (nickname) + ".",
      i18n("trainNowSleepLikeAChampionLater15d2672") + (nickname) + ".",
      i18n("theDayIsnTOverUntilYouMove57cf5fe") + (nickname) + ".",
      i18n("eveningEdition5696108") + (nickname) + i18n("theWeightsAreStillWarm7b8a706"),
      i18n("theBestTimeWasThisMorningTheSecondbc0aef8") + (nickname) + ".",
      i18n("dedicationLooksGoodOnYou7e7964f") + (nickname) + ".",
    ];
    const night = [
      i18n("aTrueChampion483d1f4") + (nickname) + i18n("orAnInsomniacEitherWayLetSGo18a41d1"),
      i18n("everyoneElseIsAsleep3996bf0") + (nickname) + i18n("thisIsYourMomentce39f71"),
      i18n("nightOwlModeActivatedc6ea0aa") + (nickname) + i18n("theWeightsDonTJudge5c9cfe5"),
      i18n("canTSleepMightAsWellGetStronger928dcf6") + (nickname) + ".",
      i18n("midnightHustle3333fcf") + (nickname) + i18n("respectbf97b93"),
      i18n("theIronNeverSleepsba0aebe") + (nickname) + i18n("neitherDoYouApparentlyb95a33c"),
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
      <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>{i18n("milosTraining5b1a1c1")}</p>

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
          {quote?.body ?? i18n("yourTrainingIsInMotioncfd94f0")}
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
          <span className="text-sm font-semibold" style={{ color: "var(--dim)" }}>{i18n("dayStreakca360c4")}</span>
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
            <span className="text-sm font-semibold" style={{ color: "var(--dim)" }}>{i18n("advancements7f59df0")}</span>
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
              animation: "fadeInUp 0.4s ease both",
              animationDelay: (idx * 80) + "ms",
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
            {i18n("completeYourFirstWorkoutToEarnYourFirst4d6cd86")}
          </p>
        )}
      </div>
    </section>
  );
}

// ── Main component ────────────────────────────────────────────────────────────

export function LandingPage() {
  const i18n = useUiTranslations();
  const uiLocale = useUiLocale();
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
  const ctaNow = useMemo(() => new Date(), []);
  const ctaScheduleWindow = useMemo(() => ({
    startAt: new Date(ctaNow.getTime() - 2 * 60 * 60 * 1_000).toISOString(),
    endAt: new Date(ctaNow.getTime() + 3 * 24 * 60 * 60 * 1_000).toISOString(),
  }), [ctaNow]);

  const landingQuery = useQuery({
    queryKey: ["landing"],
    enabled: Boolean(tokens?.access_token),
    queryFn: async () => {
      if (!tokens?.access_token) throw new Error(i18n("authenticationRequired9e44e0b"));
      return fetchLandingPayload(tokens.access_token);
    },
  });

  const ctaScheduleQuery = useQuery({
    queryKey: ["landing", "workout-cta", "schedule", ctaScheduleWindow.startAt],
    enabled: Boolean(tokens?.access_token) && currentUser?.role === "member",
    queryFn: () =>
      fetchSchedule(tokens!.access_token, {
        startAt: ctaScheduleWindow.startAt,
        endAt: ctaScheduleWindow.endAt,
        days: 3,
        classTypeIds: [],
      }),
    staleTime: 60_000,
  });

  const ctaAssignmentsQuery = useQuery({
    queryKey: ["landing", "workout-cta", "assignments", formatLocalIsoDate(ctaNow)],
    enabled: Boolean(tokens?.access_token) && currentUser?.role === "athlete",
    queryFn: () => fetchAssignedWorkoutWeek(tokens!.access_token, formatLocalIsoDate(ctaNow)),
    staleTime: 60_000,
  });

  const toggleLeaderboard = useMutation({
    mutationFn: async (optedIn: boolean) => {
      if (!tokens?.access_token) throw new Error(i18n("authenticationRequired9e44e0b"));
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
        throw new Error(i18n("executionNotAvailablea9817d4"));
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
          <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>{i18n("milosTraining5b1a1c1")}</p>
          <h1 className="mt-4 text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "var(--text)" }}>
            {i18n("loadingYourTrainingOverview39806c7")}
          </h1>
        </div>
      </main>
    );
  }

  if (landingQuery.isError || !landing) {
    const message =
      landingQuery.error instanceof Error
        ? localizeError(landingQuery.error, i18n)
        : i18n("theLandingPageCouldNotBeLoaded0cdbfb4");

    return (
      <main className="min-h-screen px-6 py-10 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
        <div className="mx-auto max-w-5xl rounded-[2.4rem] p-8" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <p className="text-sm font-semibold uppercase tracking-[0.28em]" style={{ color: "var(--primary)" }}>{i18n("milosTraining5b1a1c1")}</p>
          <h1 className="mt-4 text-4xl font-semibold tracking-tight md:text-5xl" style={{ color: "var(--text)" }}>
            {i18n("yourTrainingOverviewIsUnavailable0a82b18")}
          </h1>
          <p className="mt-4 max-w-2xl text-base leading-7" style={{ color: "var(--muted)" }}>{message}</p>
          <div className="mt-6 flex flex-wrap gap-3">
            <button
              className="rounded-2xl px-5 py-3 text-sm font-semibold"
              style={{ background: "var(--text)", color: "var(--bg)" }}
              onClick={() => void landingQuery.refetch()}
              type="button"
            >
              {i18n("retry9f5cd8a")}
            </button>
            <button
              className="rounded-2xl px-5 py-3 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--border)", border: "1px solid var(--border-strong)", color: "var(--text-soft)" }}
              disabled={!tokens}
              onClick={() => void rotate()}
              type="button"
            >
              {i18n("refreshSessionf2ed411")}
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
  const leaderboardOptedIn = landing.gamification.leaderboard.opted_in;
  const hasActiveChallenges = landing.gamification.active_challenges.length > 0;
  const showChallenges = isAdmin || hasActiveChallenges;
  const collapseLeaderboard = !isAdmin && !leaderboardOptedIn;
  const logWorkoutCta = workoutCta({
    role: currentUser?.role,
    now: ctaNow,
    executions: landing.recent_executions,
    scheduleSlots: ctaScheduleQuery.data?.slots ?? [],
    assignments: ctaAssignmentsQuery.data?.assignments ?? [],
  });

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

          {!isAdmin && logWorkoutCta ? (
            <div className="sticky top-[4rem] z-30 flex justify-end">
              <Link
                href={logWorkoutCta.href}
                className="rounded-full px-5 py-3 text-sm font-bold shadow-[0_12px_30px_rgba(0,0,0,0.25)] transition-transform hover:-translate-y-0.5"
                style={{
                  background: "var(--primary)",
                  color: "var(--primary-contrast, var(--bg))",
                  border: "1px solid color-mix(in srgb, var(--primary) 70%, var(--text))",
                }}
              >
                {logWorkoutCta.label === "resume" ? i18n("resumeWorkoutc6154f0") : i18n("logWorkout5fe879b")}
              </Link>
            </div>
          ) : null}

          {/* ── Stats strip (non-admin only) ────────────────────────────── */}
          {!isAdmin && stats && (
            <section className="grid gap-4 sm:grid-cols-3">
              <article className="rounded-[1.9rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
                <div className="flex items-center gap-2">
                  <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{i18n("motivationd6a0619")}</p>
                  <HelpIcon tooltip={i18n("workoutFrequencyVsWeeklyTargetLast10Weeks28c26ce")} onClick={() => setActiveInfoModal("volume")} />
                </div>
                {isNaN(Math.round(stats.motivation_score ?? NaN)) ? (
                  <p className="mt-3 text-base font-semibold" style={{ color: "var(--dim)" }}>
                    {stats.total_workouts === 0
                      ? i18n("noWorkoutsYet85a9204")
                      : weeklyWorkoutTarget === 0
                        ? i18n("setAWeeklyTargetdd70e51")
                        : i18n("calculatingc573779")}
                  </p>
                ) : (
                  <p className="mt-3 text-3xl font-semibold tracking-tight" style={{ color: "var(--success)" }}>
                    {Math.round(stats.motivation_score)}%
                  </p>
                )}
                <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>{i18n("last10WeeksVsTarget153cf63")}</p>
              </article>

              <article className="rounded-[1.9rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
                <div className="flex items-center gap-2">
                  <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{i18n("perseverance3b53f48")}</p>
                  <HelpIcon tooltip={i18n("howCloselyYouFollowedPrescribedExercises760e833")} onClick={() => setActiveInfoModal("volume")} />
                </div>
                {isNaN(Math.round(stats.perseverance_score ?? NaN)) ? (
                  <p className="mt-3 text-base font-semibold" style={{ color: "var(--dim)" }}>
                    {stats.total_workouts === 0 ? i18n("noWorkoutsYet85a9204") : i18n("calculatingc573779")}
                  </p>
                ) : (
                  <p className="mt-3 text-3xl font-semibold tracking-tight" style={{ color: "var(--primary)" }}>
                    {Math.round(stats.perseverance_score)}%
                  </p>
                )}
                <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>{i18n("last7TrainingDays5c44037")}</p>
              </article>

              <article className="rounded-[1.9rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
                <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>{i18n("trainingVolume11e038b")}</p>
                <p className="mt-3 text-3xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>
                  {stats.total_workouts}
                </p>
                <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>
                  {stats.total_prs > 0 ? (stats.total_prs) + i18n("prs80e1569") : ""}
                  {i18n("bestStreak04df811")} {stats.longest_streak} {i18n("days5548ae4")}
                </p>
              </article>
            </section>
          )}

          {/* ── Challenges + Leaderboard ────────────────────────────────── */}
          <section className={"grid gap-6 " + (showChallenges ? "xl:grid-cols-[1.15fr_0.85fr]" : "")}>
            {showChallenges ? (
            <article id="challenges" className="rounded-[2.2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
              <div className="flex items-center justify-between gap-4">
                <div>
                  <div className="flex items-center gap-2">
                    <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>{i18n("challengesff38765")}</p>
                    <HelpIcon tooltip={i18n("whatAreChallengesfdf13a8")} onClick={() => setActiveInfoModal("challenges")} />
                  </div>
                  <h2 className="mt-3 text-2xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>{i18n("seasonalMomentum8724e0a")}</h2>
                </div>
                {isAdmin ? (
                  <Link
                    className="rounded-full px-4 py-2 text-sm font-semibold"
                    style={{ background: "var(--border)", border: "1px solid var(--border-strong)", color: "var(--text-soft)" }}
                    href="/admin/challenges"
                  >
                    {i18n("create6e157c5")}
                  </Link>
                ) : null}
              </div>
              <div className="mt-5 space-y-4">
                {landing.gamification.active_challenges.length === 0 ? (
                  <p className="rounded-2xl px-4 py-5 text-sm" style={{ background: "var(--panel-muted)", color: "var(--dim)" }}>
                    {i18n("noActiveSeasonalChallengesYetdcbdf9c")}
                  </p>
                ) : (
                  landing.gamification.active_challenges.map((challenge) => (
                    <ChallengeCard key={challenge.id} challenge={challenge} />
                  ))
                )}
              </div>
            </article>
            ) : null}

            <div className={collapseLeaderboard ? "group relative z-20 h-12 w-12 justify-self-end" : ""}>
            {collapseLeaderboard ? (
              <button
                type="button"
                className="flex h-12 w-12 items-center justify-center rounded-full text-xl opacity-45 transition hover:opacity-100 focus:opacity-100"
                style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
                aria-label={i18n("showLeaderboardOptIna95255e")}
                title={i18n("leaderboard0381247")}
              >
                🏆
              </button>
            ) : null}
            <article
              className={"rounded-[2.2rem] p-6 " + (collapseLeaderboard ? "pointer-events-none invisible absolute end-0 top-0 w-[min(28rem,calc(100vw-3rem))] opacity-0 shadow-2xl transition-all duration-200 group-hover:pointer-events-auto group-hover:visible group-hover:opacity-100 group-focus-within:pointer-events-auto group-focus-within:visible group-focus-within:opacity-100" : "")}
              style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
            >
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
                  {!isAdmin ? (
                    <button
                      className="mt-4 text-sm font-semibold underline-offset-4 hover:underline disabled:opacity-50"
                      style={{ color: "var(--dim)" }}
                      disabled={toggleLeaderboard.isPending}
                      onClick={() => void toggleLeaderboard.mutateAsync(false)}
                      type="button"
                    >
                      {i18n("leaveLeaderboard834f047")}
                    </button>
                  ) : null}
                </>
              )}
            </article>
            </div>
          </section>

          {/* ── Hall of Fame / Pantheon ────────────────────────────────── */}
          <PantheonSection />

          {/* ── Workout history ────────────────────────────────────────── */}
          {(() => {
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

            const completedWorkoutTypes = Array.from(new Set(
              landing.recent_executions
                .filter((execution) => Boolean(execution.completed_at_utc && execution.workout_type))
                .map((execution) => execution.workout_type as string),
            ));

            const filtered = landing.recent_executions.filter((ex) => {
              if (
                completedWorkoutTypes.length > 1
                && historyTypeFilter
                && (ex.workout_type ?? "session") !== historyTypeFilter
              ) return false;
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

            return (
              <HomeDisclosure
                eyebrow={i18n("workoutHistory4c84737")}
                title={i18n("recentCompletions4866ac5")}
                actions={
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
                }
              >

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
                          title={!hasData ? i18n("noWorkoutsInThisPeriodc124c5e") : undefined}
                          className="rounded-full px-3 py-1 text-xs font-semibold transition-opacity"
                          style={{
                            background: isActive ? "var(--primary)" : "var(--panel-muted)",
                            color: isActive ? "var(--primary-contrast)" : hasData ? "var(--muted)" : "var(--dim)",
                            border: isActive ? "1px solid var(--primary)" : "1px solid var(--border)",
                            opacity: hasData ? 1 : 0.45,
                            cursor: hasData ? "pointer" : "not-allowed",
                          }}
                        >
                          {d === "all" ? i18n("allTimedbad49d") : d === "week" ? i18n("thisWeek7b72883") : i18n("thisMonth1b47853")}
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
                        ? (historyDateFrom || "…") + " → " + (historyDateTo || "…")
                        : i18n("pickDateRanged34fd50")}
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

                    {completedWorkoutTypes.length > 1 ? (
                      <>
                        <div className="w-px self-stretch" style={{ background: "var(--border)" }} />

                        {/* Workout type chips */}
                        {completedWorkoutTypes.map((type) => {
                          const isActive = historyTypeFilter === type;
                          return (
                            <button
                              key={type}
                              type="button"
                              onClick={() => setHistoryTypeFilter(isActive ? null : type)}
                              className="rounded-full px-3 py-1 text-xs font-semibold capitalize transition-opacity"
                              style={{
                                background: isActive ? "var(--primary)" : "var(--panel-muted)",
                                color: isActive ? "var(--primary-contrast)" : "var(--muted)",
                                border: isActive ? "1px solid var(--primary)" : "1px solid var(--border)",
                              }}
                            >
                              <SemanticLabel value={type} />
                            </button>
                          );
                        })}
                      </>
                    ) : null}
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
                        {i18n("chooseDateRange1a5dfb1")}
                      </h3>
                      <div className="space-y-3">
                        <div className="space-y-1">
                          <label className="block text-xs font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
                            {i18n("fromOptionaldaf5b81")}
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
                            {i18n("toae79ea1")}
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
                          {i18n("cancel77dfd21")}
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
                          {i18n("applycfea419")}
                        </button>
                      </div>
                    </div>
                  </div>
                )}

                {/* Cards */}
                <div className={"mt-5 " + (historyView === "grid" ? "grid gap-3 md:grid-cols-2 xl:grid-cols-3" : "flex flex-col gap-2")}>
                  {filtered.length === 0 ? (
                    <p className="rounded-2xl px-4 py-5 text-sm" style={{ background: "var(--panel-muted)", color: "var(--dim)" }}>
                      {landing.recent_executions.length === 0
                        ? i18n("completedWorkoutsWillAppearHereOnceExecutionHistory11bbb33")
                        : i18n("noWorkoutsMatchTheseFiltersf185a0b")}
                    </p>
                  ) : (
                    filtered.map((execution) => (
                      <button
                        key={execution.id}
                        className={"rounded-[1.5rem] text-start transition-transform hover:-translate-y-0.5 " + (historyView === "list" ? "flex items-center gap-4 px-4 py-3" : "px-4 py-4")}
                        style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
                        onClick={() => setSelectedExecutionId(execution.id)}
                        type="button"
                      >
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-semibold truncate" style={{ color: "var(--text)" }}>
                            {execution.workout_title ?? i18n("workout39463a5")}
                          </p>
                          <p className="mt-1 text-xs uppercase tracking-[0.18em]" style={{ color: "var(--primary)" }}>
                            <SemanticLabel value={execution.workout_type ?? "session"} />
                            {execution.scale_level_slug ? <>· <SemanticLabel value={execution.scale_level_slug} /></> : ""}
                          </p>
                        </div>
                        <div className={historyView === "list" ? "shrink-0 text-end" : "mt-3"}>
                          <p className="text-sm" style={{ color: "var(--muted)" }}>
                            {execution.completed_at_utc
                              ? new Date(execution.completed_at_utc).toLocaleDateString(uiLocale)
                              : i18n("inProgressb6bd42e")}
                          </p>
                          <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
                            {execution.exercise_notes.length} {i18n("notec51048b")}{execution.exercise_notes.length === 1 ? "" : i18n("sa0f1490")} ·{" "}
                            {execution.section_scores.length} {i18n("score75ebcb3")}{execution.section_scores.length === 1 ? "" : i18n("sa0f1490")}
                          </p>
                        </div>
                      </button>
                    ))
                  )}
                </div>
              </HomeDisclosure>
            );
          })()}
        </div>

        {/* ── Info modals ──────────────────────────────────────────────── */}
        {activeInfoModal === "streak" ? (
          <InfoModal title={i18n("currentStreak031c4ed")} onClose={() => setActiveInfoModal(null)}>
            <p>
              <strong style={{ color: "var(--text)" }}>{i18n("whatItMeasuresbbab752")}</strong> {i18n("theNumberOfConsecutiveUserRelativeTrainingWeeks23b79ed")} {weeklyWorkoutTarget}{" "}
              {i18n("workoutc872925")}{weeklyWorkoutTarget === 1 ? "" : i18n("sa0f1490")}.
            </p>
            <p>
              <strong style={{ color: "var(--text)" }}>{i18n("howToImprove1fadc66")}</strong> {i18n("completeAtLeastfd38f65")}{" "}
              {weeklyWorkoutTarget} {i18n("workoutc872925")}{weeklyWorkoutTarget === 1 ? "" : i18n("sa0f1490")} {i18n("eachTrainingWeekAStreakShieldCanProtecte2b0f06")}
            </p>
            <p>
              <strong style={{ color: "var(--text)" }}>{i18n("whyItMatterscdfa2a6")}</strong> {i18n("streaksBuildTheHabitOfRegularWeeklyTraining48e3b44")}
            </p>
          </InfoModal>
        ) : null}

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

        {activeInfoModal === "volume" ? (
          <InfoModal title={i18n("consistencyScore4c4624c")} onClose={() => setActiveInfoModal(null)}>
            <p>
              <strong style={{ color: "var(--text)" }}>{i18n("whatItMeasuresbbab752")}</strong> {i18n("thePercentageOfWeeksInTheLast12b38b745")} {weeklyWorkoutTarget} {i18n("workoutc872925")}
              {weeklyWorkoutTarget === 1 ? "" : i18n("sa0f1490")}.
            </p>
            <p>
              <strong style={{ color: "var(--text)" }}>{i18n("howToImprove1fadc66")}</strong> {i18n("showUpConsistentlyCompleteAtLeast7695825")} {weeklyWorkoutTarget} {i18n("workoutc872925")}{weeklyWorkoutTarget === 1 ? "" : i18n("sa0f1490")} {i18n("perWeekToCountThatWeekTowardYourc1cfc10")}
            </p>
            <p>
              <strong style={{ color: "var(--text)" }}>{i18n("whyItMatterscdfa2a6")}</strong> {i18n("consistencyOverTimePredictsLongTermAthleticProgress04e2415")}
            </p>
          </InfoModal>
        ) : null}

        {activeInfoModal === "challenges" ? (
          <InfoModal title={i18n("seasonalChallengesfd69ec6")} onClose={() => setActiveInfoModal(null)}>
            <p>
              <strong style={{ color: "var(--text)" }}>{i18n("whatTheyAree294e57")}</strong> {i18n("timeLimitedGoalsSetByYourCoachOreba26f4")}
            </p>
            <p>
              <strong style={{ color: "var(--text)" }}>{i18n("howToParticipate3af38ca")}</strong> {i18n("challengesStartAutomaticallyWhenTheyGoLiveJust0dca263")}
            </p>
            <p>
              <strong style={{ color: "var(--text)" }}>{i18n("rewards9f52f32")}</strong> {i18n("completingAChallengeEarnsYouABadgeDisplayedd966d03")}
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
                  <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--dim)" }}>{i18n("workoutHistory4c84737")}</p>
                  <h3 className="mt-3 text-2xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>
                    {selectedExecution?.workout_title ?? i18n("loadingb04ba49")}
                  </h3>
                </div>
                <button
                  className="rounded-full px-4 py-2 text-sm font-semibold"
                  style={{ background: "var(--border)", border: "1px solid var(--border-strong)", color: "var(--text-soft)" }}
                  onClick={() => setSelectedExecutionId(null)}
                  type="button"
                >
                  {i18n("closebbfa773")}
                </button>
              </div>

              {selectedExecutionQuery.isPending ? (
                <p className="mt-6 text-sm" style={{ color: "var(--dim)" }}>{i18n("loadingExecutionDetailscda7566")}</p>
              ) : selectedExecution ? (
                <div className="mt-6 space-y-6">
                  <div className="grid gap-3 sm:grid-cols-3">
                    <div className="rounded-2xl px-4 py-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                      <p className="text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{i18n("type3deb745")}</p>
                      <p className="mt-2 text-sm font-semibold" style={{ color: "var(--text)" }}>{selectedExecution.workout_type ? <SemanticLabel value={selectedExecution.workout_type} /> : i18n("unknownbc7819b")}</p>
                    </div>
                    <div className="rounded-2xl px-4 py-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                      <p className="text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{i18n("scalea29f025")}</p>
                      <p className="mt-2 text-sm font-semibold" style={{ color: "var(--text)" }}><SemanticLabel value={selectedExecution.scale_level_slug ?? "base"} /></p>
                    </div>
                    <div className="rounded-2xl px-4 py-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
                      <p className="text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{i18n("completed1798b3b")}</p>
                      <p className="mt-2 text-sm font-semibold" style={{ color: "var(--text)" }}>
                        {selectedExecution.completed_at_utc ? new Date(selectedExecution.completed_at_utc).toLocaleString(uiLocale) : i18n("inProgressb6bd42e")}
                      </p>
                    </div>
                  </div>

                  <div>
                    <p className="text-sm font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{i18n("sectionScorescaef89a")}</p>
                    <div className="mt-3 space-y-2">
                      {selectedExecution.section_scores.length === 0 ? (
                        <p className="rounded-2xl px-4 py-4 text-sm" style={{ background: "var(--panel-muted)", color: "var(--dim)" }}>{i18n("noScoresWereSubmitted1a2f165")}</p>
                      ) : (
                        selectedExecution.section_scores.map((score) => (
                          <div key={score.section_id} className="rounded-2xl px-4 py-3 text-sm" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--muted)" }}>
                            <span className="font-semibold" style={{ color: "var(--text)" }}>
                              {score.section_name ?? score.section_id}
                            </span>
                            : <LocalizedScore value={score.value} scoreType={score.score_type} unit={score.unit} />
                          </div>
                        ))
                      )}
                    </div>
                  </div>

                  <div>
                    <p className="text-sm font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{i18n("modificationsAndNotes8a73e2c")}</p>
                    <div className="mt-3 space-y-3">
                      {selectedExecution.exercise_modifications.length === 0 && selectedExecution.exercise_notes.length === 0 ? (
                        <p className="rounded-2xl px-4 py-4 text-sm" style={{ background: "var(--panel-muted)", color: "var(--dim)" }}>{i18n("noExerciseNotesWereSubmittedb9552b2")}</p>
                      ) : null}
                      {selectedExecution.exercise_modifications.map((modification) => (
                        <div
                          key={modification.patch_id ?? `${modification.segment_key}:${modification.exercise_id}:${modification.field}`}
                          className="rounded px-3 py-2"
                          style={{ background: "color-mix(in srgb, var(--warning) 10%, transparent)", borderInlineStart: "4px solid color-mix(in srgb, var(--warning) 55%, transparent)" }}
                        >
                          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                            {modification.exercise_name ?? modification.section_name ?? modification.section_id}
                          </p>
                          <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>
                            {modification.field}: {String(modification.canonical_value)} → {String(modification.actual_value)}
                            {modification.set_index ? ` · ${i18n("setLabel")} ${modification.set_index}` : ""}
                          </p>
                        </div>
                      ))}
                      {selectedExecution.exercise_notes.length > 0 ? (
                        selectedExecution.exercise_notes.map((note) => (
                          <div
                            key={note.id ?? (note.exercise_id) + "-" + (note.selected_text)}
                            className="rounded px-3 py-2"
                            style={{ background: "color-mix(in srgb, var(--primary) 8%, transparent)", borderInlineStart: "4px solid color-mix(in srgb, var(--primary) 50%, transparent)" }}
                          >
                            <p className="text-sm font-medium" style={{ color: "var(--text)" }}>{note.selected_text}</p>
                            {note.note_text ? <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>{note.note_text}</p> : null}
                            {note.tags && note.tags.length > 0 ? (
                              <p className="mt-2 text-xs uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{note.tags.join(" · ")}</p>
                            ) : null}
                          </div>
                        ))
                      ) : null}
                    </div>
                  </div>
                </div>
              ) : (
                <p className="mt-6 text-sm" style={{ color: "var(--primary-strong)" }}>
                  {selectedExecutionQuery.error instanceof Error ? localizeError(selectedExecutionQuery.error, i18n) : i18n("executionDetailsCouldNotBeLoaded30a9f0a")}
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
