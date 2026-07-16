# Gamification & Workout Improvements — Frontend Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement all frontend changes for gamification metrics redesign, Pantheon PR system, workout modification tracking, hotkeys + notes in creation, SlotPopup member redesign, and workout history view toggle + filters.

**Architecture:** Next.js 15 + TypeScript + Tailwind CSS. API layer lives in `apps/web/src/api/`. Components in `apps/web/src/components/`. All state via React `useState` or Zustand stores. No new route-level data fetching patterns — follow existing `useQuery` + `apiRequest` pattern.

**Tech Stack:** React 19, Next.js 15 App Router, TypeScript, Tailwind CSS, TanStack Query v5, Zustand. All styles via inline CSS vars (`var(--primary)`, etc.) — no Tailwind color classes for semantic colors.

---

## File Map

**New files:**
- `apps/web/src/api/gamification.ts` — API client functions + TypeScript types for preferences and Pantheon PRs
- `apps/web/src/components/landing-page/OffDaysBanner.tsx` — warning banner when preferences === null
- `apps/web/src/components/landing-page/MemberHero.tsx` — extracted hero with personalized welcome (replaces inline)
- `apps/web/src/components/landing-page/StatsStrip.tsx` — 4-card stats strip (Motivation, Consistency, Perseverance, Advancement)
- `apps/web/src/components/landing-page/PantheonSection.tsx` — landing page Pantheon preview section (up to 5 cards + search)
- `apps/web/src/components/landing-page/WorkoutHistorySection.tsx` — extracted workout history with view toggle + filters
- `apps/web/src/components/pantheon/PantheonCard.tsx` — single PR card component (score, history expand, share, edit, delete)
- `apps/web/src/components/pantheon/PantheonModal.tsx` — add/edit PR modal
- `apps/web/src/app/my-workouts/pantheon/page.tsx` — full Pantheon page route
- `apps/web/src/components/workouts/execution/ModifyStepModal.tsx` — modal for per-step modification during execution
- `apps/web/src/components/workouts/execution/FinishWizard.tsx` — 3-step finish wizard (Scores → Modifications → Review)
- `apps/web/src/components/workouts/creation/ShortcutsModal.tsx` — hotkeys reference modal (`?` button)

**Modified files:**
- `apps/web/src/api/landing.ts` — extend `LandingPayload` types with new gamification fields + preferences
- `apps/web/src/api/executions.ts` — add `exercise_modifications` field to `WorkoutExecution` type; add `addModifications` API function
- `apps/web/src/components/landing-page.tsx` — replace inline MemberHero, stats strip, workout history with extracted components; add OffDaysBanner, PantheonSection
- `apps/web/src/types/workout.ts` — add `note?: string` to `DraftSection` and `DraftExercise`
- `apps/web/src/stores/workout-creation.ts` — add note fields to state + actions; update `toApiPayload()` to include notes
- `apps/web/src/components/workouts/creation/CanvasHeader.tsx` — add `?` button opening ShortcutsModal
- `apps/web/src/components/workouts/creation/MiddlePanel.tsx` — add note input fields on sections + exercises; add tooltip hotkey hints to action buttons; add `Alt+letter` keydown listener
- `apps/web/src/components/workouts/creation/WorkoutCreationCanvas.tsx` — wire `Alt+letter` hotkeys via `useEffect` keydown listener
- `apps/web/src/components/workouts/execution/WorkoutChecklist.tsx` — add "Modify this step" button per checklist item
- `apps/web/src/components/workouts/execution/ExecutionMode.tsx` — replace `CompletionReview` with `FinishWizard`; thread `exercise_modifications` state
- `apps/web/src/components/schedule/SlotPopup.tsx` — remove 3 info boxes (capacity, approval, deadline); add scale chips; add accordion (Workout Details / Conversation); add pending booking banner; add ChatSection
- `apps/web/src/components/workouts/WorkoutPreviewDetail.tsx` — render section notes + exercise notes (read-only, italic/muted style)
- `apps/web/src/components/ProfilePage.tsx` — add "Training Schedule" CollapsibleSection with off-days checkboxes

---

## Task 1: TypeScript Types + API Client

**Files:**
- Create: `apps/web/src/api/gamification.ts`
- Modify: `apps/web/src/api/landing.ts`
- Modify: `apps/web/src/api/executions.ts`

- [ ] **Step 1: Create `apps/web/src/api/gamification.ts`**

```typescript
import { apiRequest } from "@/api/client";

export type GamificationPreferences = {
  off_days: number[]; // 0=Sun … 6=Sat, max 3
};

export type PRUnit = "mins_secs" | "reps" | "sets" | "kcals" | "m" | "kg";

export type PRRecord = {
  id: string;
  user_id: string;
  name: string;
  current_score: number;
  unit: PRUnit;
  higher_is_better: boolean;
  beaten_on: string; // ISO date "YYYY-MM-DD"
  inserted_at: string;
  updated_at: string;
};

export type PRHistoryEntry = {
  id: string;
  pr_record_id: string;
  score: number;
  beaten_on: string;
  inserted_at: string;
};

export type CreatePRParams = {
  name: string;
  current_score: number;
  unit: PRUnit;
  higher_is_better: boolean;
  beaten_on: string;
};

export type UpdatePRParams = Partial<CreatePRParams>;

export async function getGamificationPreferences(token: string) {
  return apiRequest<GamificationPreferences | null>("/gamification/preferences", { token });
}

export async function updateGamificationPreferences(
  token: string,
  params: GamificationPreferences,
) {
  return apiRequest<GamificationPreferences>("/gamification/preferences", {
    method: "PUT",
    token,
    body: params,
  });
}

export async function listPRs(token: string, q?: string) {
  const search = q ? `?q=${encodeURIComponent(q)}` : "";
  return apiRequest<PRRecord[]>(`/prs${search}`, { token });
}

export async function createPR(token: string, params: CreatePRParams) {
  return apiRequest<PRRecord>("/prs", { method: "POST", token, body: params });
}

export async function updatePR(token: string, id: string, params: UpdatePRParams) {
  return apiRequest<PRRecord>(`/prs/${id}`, { method: "PATCH", token, body: params });
}

export async function deletePR(token: string, id: string) {
  return apiRequest<void>(`/prs/${id}`, { method: "DELETE", token });
}

export async function getPRHistory(token: string, id: string) {
  return apiRequest<PRHistoryEntry[]>(`/prs/${id}/history`, { token });
}

export async function sharePR(token: string, id: string) {
  return apiRequest<{ message: string }>(`/prs/${id}/share`, { method: "POST", token });
}
```

- [ ] **Step 2: Extend `LandingPayload` in `apps/web/src/api/landing.ts`**

Replace the `gamification` block type with:

```typescript
export type GamificationPreferences = {
  off_days: number[];
};

// inside LandingPayload:
gamification: {
  settings: {
    weekly_workout_target: number;
    streak_shield_reset_day: number | null;
    leaderboard_enabled: boolean;
  };
  stats: {
    current_streak: number;
    longest_streak: number;
    total_workouts: number;
    total_prs: number;
    current_streak_shields: number;
    consistency_score: number;
    last_workout_at: string | null;
    // NEW fields:
    motivation_score: number;
    perseverance_score: number;
    advancement_count: number;
  };
  preferences: GamificationPreferences | null; // NEW
  badges: BadgeRecord[];
  active_challenges: ChallengeRecord[];
  leaderboard: {
    visible: boolean;
    opted_in: boolean;
    weekly: LeaderboardEntry[];
    monthly: LeaderboardEntry[];
  };
};
```

- [ ] **Step 3: Extend `WorkoutExecution` + add modifications API in `apps/web/src/api/executions.ts`**

Add to `WorkoutExecution` type after `exercise_notes`:
```typescript
exercise_modifications: Array<{
  exercise_id: string;
  step_label: string;
  field: string;
  prescribed_value: number;
  actual_value: number | null;
  skipped: boolean;
  logged_at: string;
}>;
```

Add function at the end of the file:
```typescript
export type ExerciseModification = {
  exercise_id: string;
  step_label: string;
  field: string;
  prescribed_value: number;
  actual_value: number | null;
  skipped: boolean;
};

export async function addModifications(
  token: string,
  executionId: string,
  modifications: ExerciseModification[],
) {
  return apiRequest<WorkoutExecution>(`/executions/${executionId}/modifications`, {
    method: "POST",
    token,
    body: { modifications },
  });
}
```

- [ ] **Step 4: Commit**

```bash
git add apps/web/src/api/gamification.ts apps/web/src/api/landing.ts apps/web/src/api/executions.ts
git commit -m "feat(frontend/types): add gamification preferences + Pantheon PR + modification types"
```

---

## Task 2: Profile Page — Training Schedule Section

**Files:**
- Modify: `apps/web/src/components/ProfilePage.tsx`

- [ ] **Step 1: Add `TrainingScheduleSection` component inside `ProfilePage.tsx`**

Insert before `export function ProfilePage()`:

```typescript
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  getGamificationPreferences,
  updateGamificationPreferences,
} from "@/api/gamification";

const DAY_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function TrainingScheduleSection({ accessToken }: { accessToken: string }) {
  const queryClient = useQueryClient();

  const prefQuery = useQuery({
    queryKey: ["gamification-preferences"],
    queryFn: () => getGamificationPreferences(accessToken),
  });

  const [selectedDays, setSelectedDays] = React.useState<number[]>([]);

  // Sync state when query resolves
  React.useEffect(() => {
    if (prefQuery.data != null) {
      setSelectedDays(prefQuery.data.off_days);
    }
  }, [prefQuery.data]);

  const mutation = useMutation({
    mutationFn: (days: number[]) =>
      updateGamificationPreferences(accessToken, { off_days: days }),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["gamification-preferences"] });
      void queryClient.invalidateQueries({ queryKey: ["landing"] });
    },
  });

  function toggleDay(day: number) {
    setSelectedDays((prev) => {
      if (prev.includes(day)) return prev.filter((d) => d !== day);
      if (prev.length >= 3) return prev; // max 3
      return [...prev, day];
    });
  }

  return (
    <div className="space-y-5">
      <p className="text-sm leading-relaxed" style={{ color: "var(--text-soft)" }}>
        Select up to <strong>3 rest days</strong> per week. These days are excluded from your
        Consistency streak, Perseverance, and Motivation calculations — so a planned rest day
        won't break your progress.
      </p>

      <div className="flex flex-wrap gap-2">
        {DAY_LABELS.map((label, idx) => {
          const selected = selectedDays.includes(idx);
          const atMax = selectedDays.length >= 3 && !selected;
          return (
            <button
              key={label}
              type="button"
              disabled={atMax}
              onClick={() => toggleDay(idx)}
              className="rounded-full px-4 py-2 text-sm font-semibold transition-colors disabled:opacity-40"
              style={{
                background: selected
                  ? "color-mix(in srgb, var(--primary) 22%, transparent)"
                  : "var(--panel-muted)",
                color: selected ? "var(--primary-strong)" : "var(--text-soft)",
                border: selected
                  ? "1px solid color-mix(in srgb, var(--primary) 50%, transparent)"
                  : "1px solid var(--border)",
              }}
            >
              {label}
            </button>
          );
        })}
      </div>

      {selectedDays.length === 0 && (
        <p className="text-xs" style={{ color: "var(--dim)" }}>
          No rest days selected — all days count as training days.
        </p>
      )}

      {mutation.isError && (
        <p className="text-xs" style={{ color: "var(--danger)" }}>
          {mutation.error instanceof Error ? mutation.error.message : "Save failed"}
        </p>
      )}

      <button
        type="button"
        disabled={mutation.isPending}
        onClick={() => mutation.mutate(selectedDays)}
        className="rounded-2xl px-6 py-2.5 text-sm font-semibold disabled:opacity-50"
        style={{ background: "var(--primary)", color: "var(--bg)" }}
      >
        {mutation.isPending ? "Saving…" : "Save rest days"}
      </button>

      {mutation.isSuccess && (
        <p className="text-xs" style={{ color: "var(--lime)" }}>
          ✓ Rest days saved
        </p>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Add the section to `ProfilePage` JSX**

After the existing `<CollapsibleSection>` blocks, add:

```typescript
<CollapsibleSection
  id="training-schedule"
  title="Training Schedule"
  description="Set your weekly rest days for accurate gamification metrics."
>
  <TrainingScheduleSection accessToken={tokens.access_token} />
</CollapsibleSection>
```

- [ ] **Step 3: Run dev server and verify**

```bash
cd apps/web && npx next dev
```

Navigate to `/profile`, expand "Training Schedule", select up to 5 days, click Save, verify success message appears.

- [ ] **Step 4: Commit**

```bash
git add apps/web/src/components/ProfilePage.tsx
git commit -m "feat(frontend/profile): add Training Schedule section for off-days configuration"
```

---

## Task 3: Landing Page — Hero Redesign + Stats Strip + Off-Days Banner

**Files:**
- Create: `apps/web/src/components/landing-page/OffDaysBanner.tsx`
- Modify: `apps/web/src/components/landing-page.tsx`

- [ ] **Step 1: Create `OffDaysBanner.tsx`**

```typescript
// apps/web/src/components/landing-page/OffDaysBanner.tsx
"use client";

import Link from "next/link";

export function OffDaysBanner() {
  return (
    <div
      className="rounded-[1.8rem] p-5"
      style={{
        background: "color-mix(in srgb, var(--warning) 10%, transparent)",
        border: "1px solid color-mix(in srgb, var(--warning) 35%, transparent)",
      }}
    >
      <div className="flex items-start gap-3">
        <span className="text-xl leading-none">⚠️</span>
        <div className="min-w-0">
          <p className="font-semibold" style={{ color: "var(--warning)" }}>
            Set your rest days for accurate metrics
          </p>
          <p className="mt-1.5 text-sm leading-relaxed" style={{ color: "var(--text-soft)" }}>
            Your Consistency streak, Perseverance and Motivation scores exclude your scheduled
            rest days — but we don&apos;t know which days those are yet. Without this, your
            streak may break on days you never planned to train.
          </p>
          <Link
            href="/profile#training-schedule"
            className="mt-3 inline-block text-sm font-semibold underline-offset-2 hover:underline"
            style={{ color: "var(--primary)" }}
          >
            → Set your rest days in Profile
          </Link>
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Replace `MemberHero` in `landing-page.tsx`**

Replace the entire `MemberHero` function (currently lines ~140–226) with this version that has no badge chips, no streak chip, and adds a personalized welcome:

```typescript
function MemberHero({
  nickname,
  currentStreak,
  lastWorkoutAt,
  quote,
}: {
  nickname: string;
  currentStreak: number;
  lastWorkoutAt: string | null;
  quote: TrainingQuote | null | undefined;
}) {
  const hour = new Date().getHours();
  const greeting = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening";

  const secondLine = (() => {
    if (currentStreak >= 2) return `You're on a ${currentStreak}-day streak. Keep it going.`;
    if (currentStreak === 1) return "Day 1 of your streak. Come back tomorrow.";
    if (lastWorkoutAt) {
      const days = Math.floor(
        (Date.now() - new Date(lastWorkoutAt).getTime()) / 86_400_000,
      );
      if (days === 0) return "You trained today. Well done.";
      if (days === 1) return "Last trained yesterday. Ready for today?";
      return `Last trained ${days} days ago. Let's go.`;
    }
    return "Complete your first workout to start your streak.";
  })();

  return (
    <section
      className="rounded-[2.6rem] p-8"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <p
        className="text-sm font-semibold uppercase tracking-[0.28em]"
        style={{ color: "var(--primary)" }}
      >
        Milos Training
      </p>

      {/* Personalized welcome */}
      <div className="mt-5">
        <h1 className="text-2xl font-bold md:text-3xl" style={{ color: "var(--text)" }}>
          {greeting}, {nickname}!
        </h1>
        <p className="mt-1.5 text-base" style={{ color: "var(--text-soft)" }}>
          {secondLine}
        </p>
      </div>

      {/* Quote */}
      {quote && (
        <blockquote className="mt-6 border-l-2 pl-4" style={{ borderColor: "var(--border)" }}>
          <p
            className="text-base leading-relaxed"
            style={{ color: "var(--muted)", fontStyle: "italic" }}
          >
            {quote.body}
          </p>
          {quote.author ? (
            <footer className="mt-1.5 text-xs" style={{ color: "var(--dim)" }}>
              — {quote.author}
            </footer>
          ) : null}
        </blockquote>
      )}
    </section>
  );
}
```

- [ ] **Step 3: Add `StatsStrip` component inline in `landing-page.tsx`**

After `MemberHero`, add:

```typescript
function StatsStrip({
  stats,
  onOpenConsistencyInfo,
}: {
  stats: LandingPayload["gamification"]["stats"];
  onOpenConsistencyInfo: () => void;
}) {
  const cards = [
    {
      label: "Motivation",
      value: `${Math.round(stats.motivation_score)}%`,
      sub: "Last 10 weeks on target",
      extra: null,
    },
    {
      label: "Consistency",
      value: `${stats.current_streak} days`,
      sub: `Longest: ${stats.longest_streak} days`,
      extra: (
        <button
          type="button"
          onClick={onOpenConsistencyInfo}
          className="ml-1.5 shrink-0 rounded-full px-1.5 py-0.5 text-[10px] font-bold"
          style={{
            background: "var(--border)",
            color: "var(--dim)",
          }}
          title="Consistency settings"
        >
          ⚙
        </button>
      ),
    },
    {
      label: "Perseverance",
      value: `${Math.round(stats.perseverance_score)}%`,
      sub: "Last 7 training days",
      extra: null,
    },
    {
      label: "Advancement",
      value: String(stats.advancement_count),
      sub: "Pantheon PRs beaten",
      extra: null,
    },
  ];

  return (
    <div className="grid grid-cols-2 gap-3 xl:grid-cols-4">
      {cards.map((card) => (
        <div
          key={card.label}
          className="rounded-[1.8rem] p-5"
          style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        >
          <p
            className="text-xs font-semibold uppercase tracking-[0.22em]"
            style={{ color: "var(--dim)" }}
          >
            {card.label}
          </p>
          <div className="mt-2 flex items-baseline gap-1">
            <span className="text-3xl font-bold tabular-nums" style={{ color: "var(--text)" }}>
              {card.value}
            </span>
            {card.extra}
          </div>
          <p className="mt-1.5 text-xs" style={{ color: "var(--muted)" }}>
            {card.sub}
          </p>
        </div>
      ))}
    </div>
  );
}
```

- [ ] **Step 4: Add ConsistencyInfoModal**

Add a small modal that opens when ⚙ is clicked:

```typescript
function ConsistencyInfoModal({ onClose }: { onClose: () => void }) {
  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
      style={{ background: "rgba(0,0,0,0.5)" }}
      onClick={onClose}
    >
      <div
        className="w-full max-w-sm rounded-[2rem] p-6"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        onClick={(e) => e.stopPropagation()}
      >
        <p className="font-semibold" style={{ color: "var(--text)" }}>Consistency & Rest Days</p>
        <p className="mt-3 text-sm leading-relaxed" style={{ color: "var(--text-soft)" }}>
          Your Consistency streak counts consecutive days you train — but rest days you&apos;ve
          scheduled are skipped without breaking your streak.
        </p>
        <a
          href="/profile#training-schedule"
          className="mt-4 block text-sm font-semibold"
          style={{ color: "var(--primary)" }}
          onClick={onClose}
        >
          → Configure rest days in Profile
        </a>
        <button
          type="button"
          onClick={onClose}
          className="mt-4 w-full rounded-2xl py-2 text-sm font-semibold"
          style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}
        >
          Close
        </button>
      </div>
    </div>
  );
}
```

- [ ] **Step 5: Wire up in `LandingPage` render**

In the `LandingPage` component:

1. Add state: `const [consistencyInfoOpen, setConsistencyInfoOpen] = useState(false);`
2. Replace the `<MemberHero ...>` call with:
```typescript
{landing.gamification.preferences === null && <OffDaysBanner />}
<MemberHero
  nickname={currentUser?.nickname ?? "Athlete"}
  currentStreak={landing.gamification.stats.current_streak}
  lastWorkoutAt={landing.gamification.stats.last_workout_at}
  quote={landing.quote}
/>
<StatsStrip
  stats={landing.gamification.stats}
  onOpenConsistencyInfo={() => setConsistencyInfoOpen(true)}
/>
{consistencyInfoOpen && <ConsistencyInfoModal onClose={() => setConsistencyInfoOpen(false)} />}
```
3. Remove the old streak chip + badge chips section entirely.
4. Remove the old 3-card stats strip (Consistency/Total workouts/Total PRs).

Add import at top:
```typescript
import { OffDaysBanner } from "@/components/landing-page/OffDaysBanner";
```

- [ ] **Step 6: Commit**

```bash
git add apps/web/src/components/landing-page.tsx apps/web/src/components/landing-page/OffDaysBanner.tsx
git commit -m "feat(frontend/landing): redesign hero (personalized welcome) + 4-card stats strip + off-days banner"
```

---

## Task 4: Pantheon — Landing Section

**Files:**
- Create: `apps/web/src/components/pantheon/PantheonCard.tsx`
- Create: `apps/web/src/components/pantheon/PantheonModal.tsx`
- Create: `apps/web/src/components/landing-page/PantheonSection.tsx`

- [ ] **Step 1: Create `apps/web/src/components/pantheon/PantheonCard.tsx`**

```typescript
"use client";

import React, { useState } from "react";
import type { PRHistoryEntry, PRRecord, PRUnit } from "@/api/gamification";
import { deletePR, getPRHistory, sharePR } from "@/api/gamification";

const UNIT_ACCENT: Record<PRUnit, string> = {
  kg:       "var(--primary)",
  reps:     "var(--success)",
  sets:     "var(--success)",
  m:        "#a78bfa",
  mins_secs: "var(--warning)",
  kcals:    "var(--amber, var(--warning))",
};

function formatScore(score: number, unit: PRUnit): string {
  if (unit === "mins_secs") {
    const totalSecs = Math.round(score);
    const m = Math.floor(totalSecs / 60).toString().padStart(2, "0");
    const s = (totalSecs % 60).toString().padStart(2, "0");
    return `${m}:${s}`;
  }
  return score % 1 === 0 ? String(score) : score.toFixed(2);
}

function formatDate(isoDate: string): string {
  return new Intl.DateTimeFormat("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
  }).format(new Date(isoDate));
}

type Props = {
  pr: PRRecord;
  accessToken: string;
  onEdit: (pr: PRRecord) => void;
  onDeleted: (id: string) => void;
};

export function PantheonCard({ pr, accessToken, onEdit, onDeleted }: Props) {
  const [historyOpen, setHistoryOpen] = useState(false);
  const [history, setHistory] = useState<PRHistoryEntry[] | null>(null);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [shareMsg, setShareMsg] = useState<string | null>(null);
  const [deleting, setDeleting] = useState(false);

  const accent = UNIT_ACCENT[pr.unit] ?? "var(--primary)";

  async function toggleHistory() {
    if (!historyOpen && history === null) {
      setHistoryLoading(true);
      const data = await getPRHistory(accessToken, pr.id);
      setHistory(data);
      setHistoryLoading(false);
    }
    setHistoryOpen((v) => !v);
  }

  async function handleShare() {
    const result = await sharePR(accessToken, pr.id);
    setShareMsg(result.message);
    setTimeout(() => setShareMsg(null), 3000);
  }

  async function handleDelete() {
    if (!window.confirm(`Delete PR "${pr.name}"? This cannot be undone.`)) return;
    setDeleting(true);
    await deletePR(accessToken, pr.id);
    onDeleted(pr.id);
  }

  return (
    <div
      className="rounded-[1.8rem] p-5"
      style={{
        background: "var(--panel)",
        border: `1px solid color-mix(in srgb, ${accent} 25%, var(--border))`,
      }}
    >
      {/* Top row: name + date */}
      <div className="flex items-start justify-between gap-3">
        <p
          className="text-xs font-bold uppercase tracking-[0.22em]"
          style={{ color: "var(--dim)" }}
        >
          {pr.name}
        </p>
        <p className="shrink-0 text-xs" style={{ color: "var(--muted)" }}>
          {formatDate(pr.beaten_on)}
        </p>
      </div>

      {/* Score */}
      <div className="mt-3 flex items-end gap-3">
        <span
          className="text-4xl font-black tabular-nums"
          style={{ color: "var(--text)" }}
        >
          {formatScore(pr.current_score, pr.unit)}
        </span>
        <span
          className="mb-1 text-sm font-semibold"
          style={{ color: accent }}
        >
          {pr.unit === "mins_secs" ? "mm:ss" : pr.unit}
        </span>
        <span
          className="mb-1.5 ml-auto text-[11px]"
          style={{ color: "var(--dim)" }}
          title={pr.higher_is_better ? "Higher score is better" : "Lower score is better"}
        >
          {pr.higher_is_better ? "↑" : "↓"}
        </span>
      </div>

      {/* Action row */}
      <div className="mt-4 flex flex-wrap items-center gap-2">
        <button
          type="button"
          onClick={toggleHistory}
          className="text-xs font-semibold"
          style={{ color: "var(--primary)" }}
        >
          {historyOpen ? "History ▴" : "History ▾"}
        </button>
        <div className="flex-1" />
        <button
          type="button"
          onClick={handleShare}
          className="rounded-xl px-2.5 py-1 text-xs font-semibold"
          style={{ background: "var(--panel-muted)", color: "var(--text-soft)", border: "1px solid var(--border)" }}
        >
          Share →
        </button>
        <button
          type="button"
          onClick={() => onEdit(pr)}
          className="rounded-xl px-2.5 py-1 text-xs font-semibold"
          style={{ background: "var(--panel-muted)", color: "var(--text-soft)", border: "1px solid var(--border)" }}
        >
          Edit
        </button>
        <button
          type="button"
          onClick={handleDelete}
          disabled={deleting}
          className="rounded-xl px-2.5 py-1 text-xs font-semibold disabled:opacity-50"
          style={{ color: "var(--danger)", border: "1px solid color-mix(in srgb, var(--danger) 30%, var(--border))" }}
        >
          ✕
        </button>
      </div>

      {/* Share message toast */}
      {shareMsg && (
        <p
          className="mt-3 rounded-xl px-3 py-2 text-xs font-medium"
          style={{ background: "var(--panel-muted)", color: "var(--text-soft)", border: "1px solid var(--border)" }}
        >
          {shareMsg}
        </p>
      )}

      {/* History expand */}
      {historyOpen && (
        <div className="mt-4 space-y-2 border-t pt-4" style={{ borderColor: "var(--border)" }}>
          {historyLoading ? (
            <p className="text-xs" style={{ color: "var(--dim)" }}>Loading…</p>
          ) : history && history.length > 0 ? (
            history.map((entry) => (
              <div key={entry.id} className="flex items-center justify-between">
                <span className="text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
                  {formatScore(entry.score, pr.unit)}{" "}
                  <span className="text-xs" style={{ color: accent }}>{pr.unit}</span>
                </span>
                <span className="text-xs" style={{ color: "var(--dim)" }}>
                  {formatDate(entry.beaten_on)}
                </span>
              </div>
            ))
          ) : (
            <p className="text-xs" style={{ color: "var(--dim)" }}>No history yet.</p>
          )}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 2: Create `apps/web/src/components/pantheon/PantheonModal.tsx`**

```typescript
"use client";

import React, { useEffect, useState } from "react";
import type { CreatePRParams, PRRecord, PRUnit } from "@/api/gamification";

const PR_UNITS: { value: PRUnit; label: string }[] = [
  { value: "kg", label: "kg" },
  { value: "reps", label: "reps" },
  { value: "sets", label: "sets" },
  { value: "m", label: "meters" },
  { value: "mins_secs", label: "min:sec" },
  { value: "kcals", label: "kcal" },
];

type Props = {
  initial?: PRRecord;
  onSave: (params: CreatePRParams) => Promise<void>;
  onClose: () => void;
};

export function PantheonModal({ initial, onSave, onClose }: Props) {
  const today = new Date().toISOString().split("T")[0]!;

  const [name, setName] = useState(initial?.name ?? "");
  const [score, setScore] = useState(initial ? String(initial.current_score) : "");
  const [unit, setUnit] = useState<PRUnit>(initial?.unit ?? "kg");
  const [higherIsBetter, setHigherIsBetter] = useState(initial?.higher_is_better ?? true);
  const [beatenOn, setBeatenOn] = useState(initial?.beaten_on ?? today);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSave() {
    if (!name.trim() || !score) return;
    setSaving(true);
    setError(null);
    try {
      await onSave({
        name: name.trim(),
        current_score: parseFloat(score),
        unit,
        higher_is_better: higherIsBetter,
        beaten_on: beatenOn,
      });
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Save failed");
      setSaving(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
      style={{ background: "rgba(0,0,0,0.55)" }}
      onClick={onClose}
    >
      <div
        className="w-full max-w-sm space-y-4 rounded-[2rem] p-6"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        onClick={(e) => e.stopPropagation()}
      >
        <p className="text-base font-bold" style={{ color: "var(--text)" }}>
          {initial ? "Edit PR" : "Add PR"}
        </p>

        <div className="space-y-3">
          <input
            type="text"
            placeholder="PR name (e.g. Back Squat)"
            value={name}
            onChange={(e) => setName(e.target.value)}
            className="w-full rounded-xl px-4 py-2.5 text-sm outline-none"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          />

          <div className="flex gap-2">
            <input
              type="number"
              placeholder="Score"
              value={score}
              onChange={(e) => setScore(e.target.value)}
              className="min-w-0 flex-1 rounded-xl px-4 py-2.5 text-sm outline-none"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            />
            <select
              value={unit}
              onChange={(e) => setUnit(e.target.value as PRUnit)}
              className="rounded-xl px-3 py-2.5 text-sm outline-none"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            >
              {PR_UNITS.map((u) => (
                <option key={u.value} value={u.value}>{u.label}</option>
              ))}
            </select>
          </div>

          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => setHigherIsBetter(true)}
              className="flex-1 rounded-xl py-2.5 text-sm font-semibold"
              style={{
                background: higherIsBetter
                  ? "color-mix(in srgb, var(--primary) 22%, transparent)"
                  : "var(--panel-muted)",
                color: higherIsBetter ? "var(--primary-strong)" : "var(--text-soft)",
                border: higherIsBetter
                  ? "1px solid color-mix(in srgb, var(--primary) 50%, transparent)"
                  : "1px solid var(--border)",
              }}
            >
              ↑ Higher is better
            </button>
            <button
              type="button"
              onClick={() => setHigherIsBetter(false)}
              className="flex-1 rounded-xl py-2.5 text-sm font-semibold"
              style={{
                background: !higherIsBetter
                  ? "color-mix(in srgb, var(--primary) 22%, transparent)"
                  : "var(--panel-muted)",
                color: !higherIsBetter ? "var(--primary-strong)" : "var(--text-soft)",
                border: !higherIsBetter
                  ? "1px solid color-mix(in srgb, var(--primary) 50%, transparent)"
                  : "1px solid var(--border)",
              }}
            >
              ↓ Lower is better
            </button>
          </div>

          <div>
            <label className="text-xs font-semibold" style={{ color: "var(--dim)" }}>
              Date beaten
            </label>
            <input
              type="date"
              value={beatenOn}
              onChange={(e) => setBeatenOn(e.target.value)}
              className="mt-1 w-full rounded-xl px-4 py-2.5 text-sm outline-none"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            />
          </div>
        </div>

        {error && (
          <p className="text-xs" style={{ color: "var(--danger)" }}>{error}</p>
        )}

        <div className="flex gap-2">
          <button
            type="button"
            onClick={onClose}
            className="flex-1 rounded-2xl py-2.5 text-sm font-semibold"
            style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={saving || !name.trim() || !score}
            onClick={handleSave}
            className="flex-1 rounded-2xl py-2.5 text-sm font-semibold disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--bg)" }}
          >
            {saving ? "Saving…" : "Save"}
          </button>
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 3: Create `apps/web/src/components/landing-page/PantheonSection.tsx`**

```typescript
"use client";

import React, { useCallback, useState } from "react";
import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  createPR,
  listPRs,
  updatePR,
  type CreatePRParams,
  type PRRecord,
} from "@/api/gamification";
import { PantheonCard } from "@/components/pantheon/PantheonCard";
import { PantheonModal } from "@/components/pantheon/PantheonModal";

export function PantheonSection({ accessToken }: { accessToken: string }) {
  const queryClient = useQueryClient();
  const [search, setSearch] = useState("");
  const [modalOpen, setModalOpen] = useState(false);
  const [editTarget, setEditTarget] = useState<PRRecord | null>(null);

  const prsQuery = useQuery({
    queryKey: ["prs", search],
    queryFn: () => listPRs(accessToken, search || undefined),
  });

  const prs = (prsQuery.data ?? []).slice(0, 5);

  const createMutation = useMutation({
    mutationFn: (params: CreatePRParams) => createPR(accessToken, params),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ["prs"] }),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, params }: { id: string; params: CreatePRParams }) =>
      updatePR(accessToken, id, params),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ["prs"] }),
  });

  const handleSave = useCallback(
    async (params: CreatePRParams) => {
      if (editTarget) {
        await updateMutation.mutateAsync({ id: editTarget.id, params });
      } else {
        await createMutation.mutateAsync(params);
      }
    },
    [editTarget, createMutation, updateMutation],
  );

  function handleDeleted(id: string) {
    queryClient.setQueryData<PRRecord[]>(["prs", search], (old) =>
      (old ?? []).filter((p) => p.id !== id),
    );
  }

  return (
    <section
      className="rounded-[2.2rem] p-6"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div className="flex items-center justify-between gap-4">
        <div>
          <p
            className="text-sm font-semibold uppercase tracking-[0.24em]"
            style={{ color: "var(--dim)" }}
          >
            Pantheon
          </p>
          <h2
            className="mt-1 text-2xl font-semibold tracking-tight"
            style={{ color: "var(--text)" }}
          >
            Hall of Fame
          </h2>
        </div>
        <button
          type="button"
          onClick={() => { setEditTarget(null); setModalOpen(true); }}
          className="rounded-2xl px-4 py-2 text-sm font-semibold"
          style={{ background: "var(--primary)", color: "var(--bg)" }}
        >
          + Add PR
        </button>
      </div>

      <input
        type="text"
        placeholder="Search PRs…"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
        className="mt-4 w-full rounded-xl px-4 py-2.5 text-sm outline-none"
        style={{
          background: "var(--panel-muted)",
          border: "1px solid var(--border)",
          color: "var(--text)",
        }}
      />

      <div className="mt-4 space-y-3">
        {prsQuery.isLoading ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>Loading…</p>
        ) : prs.length === 0 ? (
          <p
            className="rounded-2xl px-4 py-5 text-sm"
            style={{ background: "var(--panel-muted)", color: "var(--dim)" }}
          >
            {search ? "No PRs match your search." : "Add your first PR to start your Pantheon."}
          </p>
        ) : (
          prs.map((pr) => (
            <PantheonCard
              key={pr.id}
              pr={pr}
              accessToken={accessToken}
              onEdit={(p) => { setEditTarget(p); setModalOpen(true); }}
              onDeleted={handleDeleted}
            />
          ))
        )}
      </div>

      {(prsQuery.data?.length ?? 0) > 5 && (
        <Link
          href="/my-workouts/pantheon"
          className="mt-4 block text-center text-sm font-semibold"
          style={{ color: "var(--primary)" }}
        >
          View all →
        </Link>
      )}

      {modalOpen && (
        <PantheonModal
          initial={editTarget ?? undefined}
          onSave={handleSave}
          onClose={() => setModalOpen(false)}
        />
      )}
    </section>
  );
}
```

- [ ] **Step 4: Wire PantheonSection into `landing-page.tsx`**

Import and add after the workout history section, before closing the non-admin content area:

```typescript
import { PantheonSection } from "@/components/landing-page/PantheonSection";

// In render, after workout history section:
{!isAdmin && tokens?.access_token && (
  <PantheonSection accessToken={tokens.access_token} />
)}
```

- [ ] **Step 5: Commit**

```bash
git add apps/web/src/components/pantheon/ apps/web/src/components/landing-page/PantheonSection.tsx apps/web/src/components/landing-page.tsx
git commit -m "feat(frontend/pantheon): Pantheon landing section — PR cards, search, add/edit/delete/share"
```

---

## Task 5: Full Pantheon Page

**Files:**
- Create: `apps/web/src/app/my-workouts/pantheon/page.tsx`

- [ ] **Step 1: Create full Pantheon page at `/my-workouts/pantheon`**

```typescript
// apps/web/src/app/my-workouts/pantheon/page.tsx
import { AuthGuard } from "@/components/auth-guard";
import { PantheonPage } from "@/components/pantheon/PantheonPage";

export const dynamic = "force-dynamic";

export default function PantheonRoute() {
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <PantheonPage />
    </AuthGuard>
  );
}
```

- [ ] **Step 2: Create `apps/web/src/components/pantheon/PantheonPage.tsx`**

```typescript
"use client";

import React, { useCallback, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import {
  createPR,
  listPRs,
  updatePR,
  type CreatePRParams,
  type PRRecord,
} from "@/api/gamification";
import { useSession } from "@/components/session-provider";
import { PantheonCard } from "@/components/pantheon/PantheonCard";
import { PantheonModal } from "@/components/pantheon/PantheonModal";

export function PantheonPage() {
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const [search, setSearch] = useState("");
  const [modalOpen, setModalOpen] = useState(false);
  const [editTarget, setEditTarget] = useState<PRRecord | null>(null);

  const prsQuery = useQuery({
    queryKey: ["prs-full", search],
    queryFn: () => listPRs(tokens!.access_token, search || undefined),
    enabled: !!tokens,
  });

  const createMutation = useMutation({
    mutationFn: (params: CreatePRParams) => createPR(tokens!.access_token, params),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ["prs-full"] }),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, params }: { id: string; params: CreatePRParams }) =>
      updatePR(tokens!.access_token, id, params),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ["prs-full"] }),
  });

  const handleSave = useCallback(
    async (params: CreatePRParams) => {
      if (editTarget) {
        await updateMutation.mutateAsync({ id: editTarget.id, params });
      } else {
        await createMutation.mutateAsync(params);
      }
    },
    [editTarget, createMutation, updateMutation],
  );

  function handleDeleted(id: string) {
    queryClient.setQueryData<PRRecord[]>(["prs-full", search], (old) =>
      (old ?? []).filter((p) => p.id !== id),
    );
  }

  const prs = prsQuery.data ?? [];

  return (
    <div className="min-h-screen" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-3xl px-4 py-8 md:py-12">
        <div className="flex items-center justify-between gap-4">
          <div>
            <p
              className="text-sm font-semibold uppercase tracking-[0.28em]"
              style={{ color: "var(--dim)" }}
            >
              Pantheon
            </p>
            <h1
              className="mt-1 text-3xl font-bold tracking-tight"
              style={{ color: "var(--text)" }}
            >
              Hall of Fame
            </h1>
            <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>
              {prs.length} personal record{prs.length !== 1 ? "s" : ""}
            </p>
          </div>
          <button
            type="button"
            onClick={() => { setEditTarget(null); setModalOpen(true); }}
            className="rounded-2xl px-5 py-2.5 text-sm font-semibold"
            style={{ background: "var(--primary)", color: "var(--bg)" }}
          >
            + Add PR
          </button>
        </div>

        <input
          type="text"
          placeholder="Search PRs…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          className="mt-6 w-full rounded-xl px-4 py-3 text-sm outline-none"
          style={{
            background: "var(--panel)",
            border: "1px solid var(--border)",
            color: "var(--text)",
          }}
        />

        <div className="mt-6 space-y-4">
          {prsQuery.isLoading ? (
            <p className="text-sm" style={{ color: "var(--dim)" }}>Loading your PRs…</p>
          ) : prs.length === 0 ? (
            <div
              className="rounded-[2rem] px-6 py-10 text-center"
              style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
            >
              <p className="text-xl font-semibold" style={{ color: "var(--text)" }}>
                Your Pantheon awaits
              </p>
              <p className="mt-2 text-sm" style={{ color: "var(--muted)" }}>
                {search
                  ? "No PRs match your search."
                  : "Track your personal bests here — each PR is a milestone worth celebrating."}
              </p>
              {!search && (
                <button
                  type="button"
                  onClick={() => { setEditTarget(null); setModalOpen(true); }}
                  className="mt-4 rounded-2xl px-6 py-2.5 text-sm font-semibold"
                  style={{ background: "var(--primary)", color: "var(--bg)" }}
                >
                  Add your first PR
                </button>
              )}
            </div>
          ) : (
            prs.map((pr) => (
              <PantheonCard
                key={pr.id}
                pr={pr}
                accessToken={tokens!.access_token}
                onEdit={(p) => { setEditTarget(p); setModalOpen(true); }}
                onDeleted={handleDeleted}
              />
            ))
          )}
        </div>
      </div>

      {modalOpen && (
        <PantheonModal
          initial={editTarget ?? undefined}
          onSave={handleSave}
          onClose={() => setModalOpen(false)}
        />
      )}
    </div>
  );
}
```

- [ ] **Step 3: Commit**

```bash
git add apps/web/src/app/my-workouts/pantheon/ apps/web/src/components/pantheon/PantheonPage.tsx
git commit -m "feat(frontend/pantheon): full Pantheon page at /my-workouts/pantheon"
```

---

## Task 6: Workout Modification Tracking — Execution UI

**Files:**
- Create: `apps/web/src/components/workouts/execution/ModifyStepModal.tsx`
- Modify: `apps/web/src/components/workouts/execution/WorkoutChecklist.tsx`

- [ ] **Step 1: Create `ModifyStepModal.tsx`**

```typescript
// apps/web/src/components/workouts/execution/ModifyStepModal.tsx
"use client";

import React, { useState } from "react";
import type { ChecklistStep } from "./WorkoutChecklist";

export type ModificationEntry = {
  exercise_id: string;
  step_label: string;
  field: string;
  prescribed_value: number;
  actual_value: number | null;
  skipped: boolean;
};

type FieldConfig = {
  field: string;
  label: string;
  prescribedValue: number;
};

function getFieldsForStep(step: ChecklistStep): FieldConfig[] {
  const exercise = step.exercise;
  const fields: FieldConfig[] = [];

  if (exercise.sets && exercise.sets > 0) {
    fields.push({
      field: "sets",
      label: "Sets",
      prescribedValue: exercise.sets,
    });
  }

  if (exercise.prescription_value && exercise.prescription_value > 0) {
    fields.push({
      field: exercise.prescription_unit ?? "reps",
      label: exercise.prescription_unit ?? "Reps",
      prescribedValue: exercise.prescription_value,
    });
  }

  if (exercise.load_value && exercise.load_value > 0) {
    fields.push({
      field: "kg",
      label: "Load (kg)",
      prescribedValue: exercise.load_value,
    });
  }

  return fields;
}

type Props = {
  step: ChecklistStep;
  sectionName: string;
  onSave: (entries: ModificationEntry[]) => void;
  onClose: () => void;
};

export function ModifyStepModal({ step, sectionName, onSave, onClose }: Props) {
  const fieldConfigs = getFieldsForStep(step);
  const [skipped, setSkipped] = useState(false);
  const [values, setValues] = useState<Record<string, string>>(
    Object.fromEntries(fieldConfigs.map((f) => [f.field, String(f.prescribedValue)])),
  );

  function handleSave() {
    const entries: ModificationEntry[] = fieldConfigs.map((fc) => ({
      exercise_id: step.exerciseId,
      step_label: `${sectionName} · ${step.exercise.name}${step.stepLabel ? ` (${step.stepLabel})` : ""}`,
      field: fc.field,
      prescribed_value: fc.prescribedValue,
      actual_value: skipped ? null : parseFloat(values[fc.field] ?? String(fc.prescribedValue)),
      skipped,
    }));
    onSave(entries);
    onClose();
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
      style={{ background: "rgba(0,0,0,0.55)" }}
      onClick={onClose}
    >
      <div
        className="w-full max-w-sm space-y-4 rounded-[2rem] p-6"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        onClick={(e) => e.stopPropagation()}
      >
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--dim)" }}>
            {sectionName}
          </p>
          <p className="mt-1 text-base font-bold" style={{ color: "var(--text)" }}>
            {step.exercise.name}
            {step.stepLabel ? <span className="ml-2 text-sm font-normal" style={{ color: "var(--muted)" }}>{step.stepLabel}</span> : null}
          </p>
        </div>

        {/* Skipped toggle */}
        <label className="flex cursor-pointer items-center gap-3">
          <input
            type="checkbox"
            checked={skipped}
            onChange={(e) => setSkipped(e.target.checked)}
            className="h-4 w-4"
          />
          <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            Skipped entirely
          </span>
        </label>

        {/* Field inputs */}
        {!skipped && fieldConfigs.length > 0 && (
          <div className="space-y-3">
            {fieldConfigs.map((fc) => (
              <div key={fc.field}>
                <label className="text-xs font-semibold" style={{ color: "var(--dim)" }}>
                  {fc.label}
                  <span className="ml-2 font-normal" style={{ color: "var(--muted)" }}>
                    (prescribed: {fc.prescribedValue})
                  </span>
                </label>
                <input
                  type="number"
                  value={values[fc.field] ?? ""}
                  onChange={(e) =>
                    setValues((prev) => ({ ...prev, [fc.field]: e.target.value }))
                  }
                  className="mt-1 w-full rounded-xl px-4 py-2.5 text-sm outline-none"
                  style={{
                    background: "var(--panel-muted)",
                    border: "1px solid var(--border)",
                    color: "var(--text)",
                  }}
                />
              </div>
            ))}
          </div>
        )}

        {fieldConfigs.length === 0 && !skipped && (
          <p className="text-sm" style={{ color: "var(--muted)" }}>
            No prescribed values to edit for this step.
          </p>
        )}

        <div className="flex gap-2">
          <button
            type="button"
            onClick={onClose}
            className="flex-1 rounded-2xl py-2.5 text-sm font-semibold"
            style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={handleSave}
            className="flex-1 rounded-2xl py-2.5 text-sm font-semibold"
            style={{ background: "var(--primary)", color: "var(--bg)" }}
          >
            Save modification
          </button>
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 2: Add "Modify this step" button to `WorkoutChecklist.tsx`**

Modify `ChecklistItemProps` to add `onModify`:
```typescript
type ChecklistItemProps = {
  step: ChecklistStep;
  checked: boolean;
  notes: ExerciseNote[];
  onToggle: () => void;
  onCreateNote: (selection: NoteSelection) => void;
  onEditNote: (note: ExerciseNote) => void;
  onModify: () => void;        // NEW
  modifiedIds: Set<string>;    // NEW — which stepIds have a saved modification
};
```

In `ChecklistItem`, after the existing note/check UI, add a subtle button:
```typescript
<button
  type="button"
  onClick={(e) => { e.stopPropagation(); props.onModify(); }}
  className="mt-1 text-[11px] font-semibold opacity-60 hover:opacity-100 transition-opacity"
  style={{ color: "var(--primary)" }}
>
  {props.modifiedIds.has(props.step.stepId) ? "✎ Modified" : "Modify this step"}
</button>
```

In `WorkoutChecklist` props add:
```typescript
onModify: (step: ChecklistStep, sectionName: string) => void;
modifiedStepIds: Set<string>;
```

Wire through to each `ChecklistItem`.

- [ ] **Step 3: Commit**

```bash
git add apps/web/src/components/workouts/execution/ModifyStepModal.tsx apps/web/src/components/workouts/execution/WorkoutChecklist.tsx
git commit -m "feat(frontend/execution): add ModifyStepModal + 'Modify this step' button per checklist item"
```

---

## Task 7: Three-Step Finish Wizard

**Files:**
- Create: `apps/web/src/components/workouts/execution/FinishWizard.tsx`
- Modify: `apps/web/src/components/workouts/execution/ExecutionMode.tsx`

- [ ] **Step 1: Create `FinishWizard.tsx`**

```typescript
// apps/web/src/components/workouts/execution/FinishWizard.tsx
"use client";

import React, { useState } from "react";
import type { TimerSegment } from "@/api/executions";
import type { ModificationEntry } from "./ModifyStepModal";
import { ModifyStepModal } from "./ModifyStepModal";
import type { ChecklistStep } from "./WorkoutChecklist";

type Score = {
  section_id: string;
  section_name?: string | null;
  value: number | string;
  unit?: string;
  score_type?: string;
  source?: string;
  kind?: string;
};

type Props = {
  scores: Score[];
  segments: TimerSegment[];
  modifications: ModificationEntry[];
  isSaving: boolean;
  feedback: string | null;
  onConfirm: (editedScores: Score[], modifications: ModificationEntry[]) => void;
};

export function FinishWizard({
  scores,
  segments,
  modifications: initialModifications,
  isSaving,
  feedback,
  onConfirm,
}: Props) {
  const [step, setStep] = useState<1 | 2 | 3>(1);
  const [editedScores, setEditedScores] = useState(() =>
    scores.map((s) => ({ ...s, value: String(s.value) })),
  );
  const [modifications, setModifications] = useState(initialModifications);
  const [modifyTarget, setModifyTarget] = useState<{
    step: ChecklistStep;
    sectionName: string;
  } | null>(null);

  function updateValue(sectionId: string, value: string) {
    setEditedScores((current) =>
      current.map((s) => (s.section_id === sectionId ? { ...s, value } : s)),
    );
  }

  function handleFinish() {
    const parsed = editedScores.map((s) => ({
      ...s,
      value: s.value === "" ? 0 : isNaN(Number(s.value)) ? s.value : Number(s.value),
    }));
    onConfirm(parsed, modifications);
  }

  function handleAddModification(entries: ModificationEntry[]) {
    setModifications((prev) => [...prev, ...entries]);
  }

  function handleRemoveModification(idx: number) {
    setModifications((prev) => prev.filter((_, i) => i !== idx));
  }

  return (
    <div
      className="flex h-screen flex-col"
      style={{ background: "var(--bg)", color: "var(--text)" }}
    >
      {/* Step indicator */}
      <div className="flex items-center justify-center gap-3 px-6 py-4 border-b" style={{ borderColor: "var(--border)" }}>
        {([1, 2, 3] as const).map((s) => (
          <div
            key={s}
            className="flex items-center gap-2"
          >
            <div
              className="flex h-7 w-7 items-center justify-center rounded-full text-xs font-bold"
              style={{
                background: s === step ? "var(--primary)" : s < step ? "var(--success)" : "var(--panel-muted)",
                color: s <= step ? "var(--bg)" : "var(--muted)",
              }}
            >
              {s < step ? "✓" : s}
            </div>
            <span className="hidden text-xs font-semibold sm:block" style={{ color: s === step ? "var(--text)" : "var(--dim)" }}>
              {s === 1 ? "Scores" : s === 2 ? "Modifications" : "Review"}
            </span>
            {s < 3 && <span className="text-xs" style={{ color: "var(--dim)" }}>›</span>}
          </div>
        ))}
      </div>

      <div className="flex flex-1 flex-col items-center overflow-y-auto p-8">

        {/* Step 1: Scores */}
        {step === 1 && (
          <>
            <div className="text-4xl mb-4">🏁</div>
            <h2 className="text-xl font-bold mb-2">Review Your Scores</h2>
            {editedScores.length > 0 ? (
              <div className="w-full max-w-sm space-y-3 mt-4">
                {editedScores.map((score) => {
                  const label =
                    score.section_name ??
                    segments.find((seg) => seg.section_id === score.section_id)?.section_name ??
                    score.section_id;
                  return (
                    <div
                      key={score.section_id}
                      className="flex items-center justify-between gap-4 rounded-xl px-4 py-3"
                      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
                    >
                      <span className="text-sm truncate" style={{ color: "var(--muted)" }}>{label}</span>
                      <div className="flex shrink-0 items-center gap-1.5">
                        <input
                          className="w-20 rounded-lg px-2 py-1 text-right text-sm font-semibold outline-none"
                          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
                          value={score.value}
                          onChange={(e) => updateValue(score.section_id, e.target.value)}
                        />
                        {score.unit && <span className="text-xs" style={{ color: "var(--muted)" }}>{score.unit}</span>}
                      </div>
                    </div>
                  );
                })}
              </div>
            ) : (
              <p className="mt-4 text-sm text-center" style={{ color: "var(--muted)" }}>
                No scoreable sections in this workout.
              </p>
            )}
          </>
        )}

        {/* Step 2: Modifications */}
        {step === 2 && (
          <>
            <div className="text-4xl mb-4">✎</div>
            <h2 className="text-xl font-bold mb-2">Modifications</h2>
            <p className="text-sm text-center mb-4" style={{ color: "var(--muted)" }}>
              Review modifications logged during the workout. Add more if needed.
            </p>
            <div className="w-full max-w-sm space-y-3">
              {modifications.length === 0 ? (
                <p className="text-sm text-center" style={{ color: "var(--dim)" }}>
                  No modifications logged yet.
                </p>
              ) : (
                modifications.map((mod, idx) => (
                  <div
                    key={idx}
                    className="flex items-start justify-between gap-3 rounded-xl px-4 py-3"
                    style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
                  >
                    <div className="min-w-0">
                      <p className="text-xs font-semibold" style={{ color: "var(--dim)" }}>{mod.step_label}</p>
                      <p className="mt-0.5 text-sm" style={{ color: "var(--text)" }}>
                        {mod.skipped
                          ? "Skipped entirely"
                          : `${mod.field}: ${mod.prescribed_value} → ${mod.actual_value ?? "—"}`}
                      </p>
                    </div>
                    <button
                      type="button"
                      onClick={() => handleRemoveModification(idx)}
                      className="text-xs shrink-0"
                      style={{ color: "var(--danger)" }}
                    >
                      ✕
                    </button>
                  </div>
                ))
              )}
            </div>
          </>
        )}

        {/* Step 3: Review */}
        {step === 3 && (
          <>
            <div className="text-4xl mb-4">⭐</div>
            <h2 className="text-xl font-bold mb-2">All set!</h2>
            <p className="text-sm text-center" style={{ color: "var(--muted)", maxWidth: "22rem" }}>
              Great work! Your scores and modifications are ready to be saved.
            </p>
            <div className="mt-4 w-full max-w-sm space-y-2">
              <p className="text-xs font-semibold" style={{ color: "var(--dim)" }}>
                {editedScores.length} score{editedScores.length !== 1 ? "s" : ""} ·{" "}
                {modifications.length} modification{modifications.length !== 1 ? "s" : ""}
              </p>
            </div>
          </>
        )}

        {feedback && (
          <p className="mt-4 text-sm text-center" style={{ color: "var(--primary-strong)" }}>{feedback}</p>
        )}
      </div>

      {/* Footer navigation */}
      <div
        className="flex items-center justify-between gap-3 px-6 py-4 border-t"
        style={{ borderColor: "var(--border)" }}
      >
        {step > 1 ? (
          <button
            type="button"
            onClick={() => setStep((s) => (s - 1) as 1 | 2 | 3)}
            className="rounded-2xl px-5 py-2.5 text-sm font-semibold"
            style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}
          >
            ← Back
          </button>
        ) : (
          <div />
        )}

        <div className="flex gap-2">
          {step < 3 && (
            <button
              type="button"
              onClick={() => setStep((s) => (s + 1) as 2 | 3)}
              className="rounded-2xl px-5 py-2.5 text-sm font-semibold"
              style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}
            >
              Skip
            </button>
          )}
          {step < 3 ? (
            <button
              type="button"
              onClick={() => setStep((s) => (s + 1) as 2 | 3)}
              className="rounded-2xl px-5 py-2.5 text-sm font-semibold"
              style={{ background: "var(--primary)", color: "var(--bg)" }}
            >
              Next →
            </button>
          ) : (
            <button
              type="button"
              onClick={handleFinish}
              disabled={isSaving}
              className="rounded-2xl px-8 py-2.5 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--lime)", color: "var(--bg)" }}
            >
              {isSaving ? "Saving…" : "Save & Done"}
            </button>
          )}
        </div>
      </div>

      {/* Modify step modal (for adding more from Step 2) */}
      {modifyTarget && (
        <ModifyStepModal
          step={modifyTarget.step}
          sectionName={modifyTarget.sectionName}
          onSave={handleAddModification}
          onClose={() => setModifyTarget(null)}
        />
      )}
    </div>
  );
}
```

- [ ] **Step 2: Replace `CompletionReview` with `FinishWizard` in `ExecutionMode.tsx`**

1. Remove the `CompletionReview` function definition.
2. Add import: `import { FinishWizard } from "./FinishWizard";`
3. Add state: `const [exerciseModifications, setExerciseModifications] = useState<ModificationEntry[]>([]);`
4. Add import: `import type { ModificationEntry } from "./ModifyStepModal";`
5. Replace the `<CompletionReview ...>` render with:
```typescript
<FinishWizard
  scores={pendingFinish.scores}
  segments={segments}
  modifications={exerciseModifications}
  isSaving={isSaving}
  feedback={feedback}
  onConfirm={(editedScores, mods) => void handleSaveCompletion(editedScores, mods)}
/>
```
6. Update `handleSaveCompletion` signature to accept `mods: ModificationEntry[]` and pass them to `completeExecutionRequest` body as `exercise_modifications`.
7. Pass `onModify` + `modifiedStepIds` down to `WorkoutChecklist`:
```typescript
const [exerciseModifications, setExerciseModifications] = useState<ModificationEntry[]>([]);
const modifiedStepIds = useMemo(
  () => new Set(exerciseModifications.map((m) => `${m.exercise_id}`)),
  [exerciseModifications],
);

function handleModify(step: ChecklistStep, sectionName: string) {
  // open ModifyStepModal, then push result to exerciseModifications
  setModifyTarget({ step, sectionName });
}
```
Add `ModifyStepModal` render inside `ExecutionMode` for inline use during the workout (not just in the wizard).

- [ ] **Step 3: Commit**

```bash
git add apps/web/src/components/workouts/execution/FinishWizard.tsx apps/web/src/components/workouts/execution/ExecutionMode.tsx
git commit -m "feat(frontend/execution): replace CompletionReview with 3-step FinishWizard; thread exercise_modifications"
```

---

## Task 8: Workout Creation — Notes + Hotkeys

**Files:**
- Modify: `apps/web/src/types/workout.ts`
- Modify: `apps/web/src/stores/workout-creation.ts`
- Create: `apps/web/src/components/workouts/creation/ShortcutsModal.tsx`
- Modify: `apps/web/src/components/workouts/creation/CanvasHeader.tsx`
- Modify: `apps/web/src/components/workouts/creation/WorkoutCreationCanvas.tsx`
- Modify: `apps/web/src/components/workouts/creation/MiddlePanel.tsx`
- Modify: `apps/web/src/components/workouts/WorkoutPreviewDetail.tsx`

- [ ] **Step 1: Add `note` to types in `apps/web/src/types/workout.ts`**

In `DraftExercise`, add:
```typescript
note: string; // coaching cue — empty string = no note
```

In `DraftSection`, add:
```typescript
note: string; // coaching cue — empty string = no note
```

In `makeDefaultExercise()`, add `note: ""` to the returned object.
In `makeDefaultSection()`, add `note: ""` to the returned object.

- [ ] **Step 2: Add note actions to workout-creation store**

In `apps/web/src/stores/workout-creation.ts`:

Add to `WorkoutCreationStore` interface:
```typescript
setSectionNote: (sectionLocalId: string, note: string) => void;
setExerciseNote: (sectionLocalId: string, exerciseLocalId: string, note: string) => void;
```

Implement:
```typescript
setSectionNote: (sectionLocalId, note) =>
  set((state) => ({
    sections: state.sections.map((s) =>
      s.localId === sectionLocalId ? { ...s, note } : s,
    ),
  })),

setExerciseNote: (sectionLocalId, exerciseLocalId, note) =>
  set((state) => ({
    sections: state.sections.map((s) =>
      s.localId === sectionLocalId
        ? {
            ...s,
            exercises: s.exercises.map((e) =>
              e.localId === exerciseLocalId ? { ...e, note } : e,
            ),
          }
        : s,
    ),
  })),
```

In `toApiPayload()`, include `note` in both the section and exercise serialization.

- [ ] **Step 3: Create `ShortcutsModal.tsx`**

```typescript
// apps/web/src/components/workouts/creation/ShortcutsModal.tsx
"use client";

type Props = { onClose: () => void };

const COLUMNS = [
  {
    heading: "Section Actions",
    shortcuts: [
      { keys: "Alt+S", label: "New section" },
      { keys: "Alt+K", label: "Duplicate section" },
      { keys: "Alt+N", label: "Section note" },
    ],
  },
  {
    heading: "Exercise Actions",
    shortcuts: [
      { keys: "Alt+E", label: "Add exercise" },
      { keys: "Alt+V", label: "Variations" },
      { keys: "Alt+A", label: "Advanced settings" },
      { keys: "Alt+P", label: "Progressive load" },
      { keys: "Alt+N", label: "Exercise note" },
      { keys: "Backspace", label: "Delete exercise" },
    ],
  },
  {
    heading: "Navigation",
    shortcuts: [
      { keys: "Tab", label: "Next exercise" },
      { keys: "⇧Tab", label: "Prev exercise" },
      { keys: "Esc", label: "Close panel" },
      { keys: "Alt+/", label: "This help" },
    ],
  },
];

export function ShortcutsModal({ onClose }: Props) {
  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
      style={{ background: "rgba(0,0,0,0.55)" }}
      onClick={onClose}
    >
      <div
        className="w-full max-w-2xl rounded-[2rem] p-8"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between mb-6">
          <p className="text-base font-bold" style={{ color: "var(--text)" }}>
            Keyboard Shortcuts
          </p>
          <button
            type="button"
            onClick={onClose}
            className="text-sm"
            style={{ color: "var(--dim)" }}
          >
            ✕
          </button>
        </div>

        <div className="grid gap-6 sm:grid-cols-3">
          {COLUMNS.map((col) => (
            <div key={col.heading}>
              <p
                className="mb-3 text-xs font-bold uppercase tracking-[0.2em]"
                style={{ color: "var(--dim)" }}
              >
                {col.heading}
              </p>
              <div className="space-y-2.5">
                {col.shortcuts.map(({ keys, label }) => (
                  <div key={keys} className="flex items-center gap-3">
                    <kbd
                      className="shrink-0 rounded-lg px-2 py-1 text-xs font-semibold"
                      style={{
                        background: "var(--panel-muted)",
                        border: "1px solid var(--border)",
                        color: "var(--text-soft)",
                        fontFamily: "monospace",
                      }}
                    >
                      {keys}
                    </kbd>
                    <span className="text-sm" style={{ color: "var(--text-soft)" }}>
                      {label}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Add `?` button to `CanvasHeader.tsx`**

1. Import: `import { ShortcutsModal } from "./ShortcutsModal";`
2. Add state: `const [shortcutsOpen, setShortcutsOpen] = useState(false);`
3. Add button before `SaveStatusIndicator` in the header:
```typescript
<button
  type="button"
  onClick={() => setShortcutsOpen(true)}
  title="Keyboard shortcuts (Alt+/)"
  className="rounded-full px-2.5 py-1.5 text-sm font-semibold"
  style={{ background: "var(--card)", color: "var(--dim)", border: "1px solid var(--dim)" }}
>
  ?
</button>
```
4. Render modal:
```typescript
{shortcutsOpen && <ShortcutsModal onClose={() => setShortcutsOpen(false)} />}
```

- [ ] **Step 5: Add global hotkey listener to `WorkoutCreationCanvas.tsx`**

Inside `WorkoutCreationCanvas`, add a `useEffect` that registers `keydown` on `document`:

```typescript
useEffect(() => {
  function handleKeyDown(e: KeyboardEvent) {
    // Do not trigger when user is typing
    if (
      document.activeElement instanceof HTMLInputElement ||
      document.activeElement instanceof HTMLTextAreaElement ||
      document.activeElement instanceof HTMLSelectElement
    ) return;

    if (!e.altKey) return;

    switch (e.key) {
      case "s":
      case "S":
        e.preventDefault();
        addSection(); // useWorkoutCreationStore action
        break;
      case "e":
      case "E":
        e.preventDefault();
        addExerciseToActiveSection(); // if active section exists
        break;
      case "/":
        e.preventDefault();
        setShortcutsOpen(true); // lift state up or use a context/event
        break;
      case "k":
      case "K":
        e.preventDefault();
        duplicateActiveSection();
        break;
      case "n":
      case "N":
        e.preventDefault();
        focusActiveNote();
        break;
      default:
        break;
    }
  }

  document.addEventListener("keydown", handleKeyDown);
  return () => document.removeEventListener("keydown", handleKeyDown);
}, [/* relevant state deps */]);
```

Note: `setShortcutsOpen` needs to be lifted to a shared context or `CanvasHeader` needs to expose an imperative handle. Simplest approach: store `shortcutsOpen` in the `useWorkoutCreationStore` Zustand store so both `WorkoutCreationCanvas` and `CanvasHeader` can read/write it.

- [ ] **Step 6: Add note inputs to `MiddlePanel.tsx`**

For each section, after the exercises list, add a note textarea:
```typescript
<div className="mt-3 px-1">
  <textarea
    placeholder="Add a coaching note for this section… (Alt+N)"
    value={section.note}
    onChange={(e) => setSectionNote(section.localId, e.target.value)}
    rows={2}
    className="w-full resize-none rounded-xl px-3 py-2 text-sm outline-none"
    style={{
      background: "var(--panel-muted)",
      border: "1px solid var(--border)",
      color: "var(--text-soft)",
      fontStyle: section.note ? "normal" : "italic",
    }}
  />
</div>
```

For each exercise, below the exercise name input, add:
```typescript
<input
  type="text"
  placeholder="Exercise note… (Alt+N)"
  value={exercise.note}
  onChange={(e) => setExerciseNote(section.localId, exercise.localId, e.target.value)}
  className="mt-1 w-full rounded-lg px-2 py-1 text-xs outline-none"
  style={{
    background: "transparent",
    border: "none",
    borderBottom: "1px solid var(--border)",
    color: "var(--dim)",
    fontStyle: "italic",
  }}
/>
```

Add tooltip-style `title` attributes to action buttons, e.g.:
```typescript
<button title="Add exercise (Alt+E)" ...>
<button title="Add section (Alt+S)" ...>
```

- [ ] **Step 7: Render notes in `WorkoutPreviewDetail.tsx`**

After the exercises list inside a section, add:
```typescript
{section.note && (
  <p
    className="mt-3 text-xs italic"
    style={{ color: "var(--dim)", paddingLeft: "0.5rem", borderLeft: "2px solid var(--border)" }}
  >
    {section.note}
  </p>
)}
```

For each exercise, below the exercise name, add:
```typescript
{exercise.note && (
  <p className="mt-0.5 text-xs italic" style={{ color: "var(--dim)" }}>
    {exercise.note}
  </p>
)}
```

The `WorkoutPreviewDetail` also receives sections from `AssignedWorkoutPanel` — the API payload will include `note` on section/exercise if the backend has been updated. Add `note?: string` to `PreviewSection` and `PreviewExercise` types.

- [ ] **Step 8: Commit**

```bash
git add apps/web/src/types/workout.ts apps/web/src/stores/workout-creation.ts apps/web/src/components/workouts/creation/ShortcutsModal.tsx apps/web/src/components/workouts/creation/CanvasHeader.tsx apps/web/src/components/workouts/creation/WorkoutCreationCanvas.tsx apps/web/src/components/workouts/creation/MiddlePanel.tsx apps/web/src/components/workouts/WorkoutPreviewDetail.tsx
git commit -m "feat(frontend/creation): coach notes on sections/exercises + Alt+letter hotkeys + ? shortcuts modal"
```

---

## Task 9: SlotPopup — Member View Redesign

**Files:**
- Modify: `apps/web/src/components/schedule/SlotPopup.tsx`

- [ ] **Step 1: Read the full current SlotPopup to understand the complete structure**

Run: `cat -n apps/web/src/components/schedule/SlotPopup.tsx`

- [ ] **Step 2: Implement redesigned SlotPopup (member view)**

The key changes, applied when `!isAdmin`:

**Remove** from non-admin view:
- The 3-card grid (Capacity, Participation approval, Deadline to book)

**Add** pending booking banner (when `!slot.auto_approve && slot.current_user_booking?.status === "pending"`):
```typescript
{!isAdmin && !slot.auto_approve && slot.current_user_booking?.status === "pending" && (
  <div
    className="mt-4 rounded-[1.4rem] p-4 text-sm"
    style={{
      background: "color-mix(in srgb, var(--warning) 10%, transparent)",
      border: "1px solid color-mix(in srgb, var(--warning) 30%, transparent)",
      color: "var(--text-soft)",
    }}
  >
    Your booking is pending approval by the class&apos;s coach. He has been notified — please
    wait a while.
  </div>
)}
```

**Add scale chips** in sticky header below workout title (same pattern as `AssignedWorkoutPanel`):

Extract scale levels from `slot.workout?.sections`:
```typescript
const scaleLevels = useMemo(() => {
  const map = new Map<string, { slug: string; label: string; sort_order: number }>();
  for (const section of slot.workout?.sections ?? []) {
    for (const exercise of section.exercises ?? []) {
      for (const variation of exercise.variations ?? []) {
        const sl = variation.scale_level;
        if (sl?.slug) map.set(sl.slug, { slug: sl.slug, label: sl.label ?? sl.slug, sort_order: sl.sort_order ?? 0 });
      }
    }
  }
  return Array.from(map.values()).sort((a, b) => a.sort_order - b.sort_order);
}, [slot.workout]);

const [activeScale, setActiveScale] = useState<string | null>(null);
```

Scale chip colors by index:
```typescript
const SCALE_COLORS = [
  "var(--primary)",
  "var(--warning)",
  "var(--success)",
  "#a78bfa",
  "var(--dim)",
];
```

In the sticky header, after the title block:
```typescript
{scaleLevels.length > 0 && (
  <div className="mt-2 flex flex-wrap gap-1.5">
    {/* Base chip */}
    <button type="button"
      onClick={() => setActiveScale(null)}
      className="rounded-full px-2.5 py-1 text-[10px] font-semibold"
      style={{
        background: activeScale === null ? SCALE_COLORS[0] : "var(--border)",
        color: activeScale === null ? "var(--bg)" : "var(--text-soft)",
        border: activeScale === null ? `1px solid ${SCALE_COLORS[0]}` : "1px solid var(--border-strong)",
      }}
    >
      Base
    </button>
    {scaleLevels.map((sl, idx) => {
      const color = SCALE_COLORS[(idx + 1) % SCALE_COLORS.length] ?? "var(--dim)";
      return (
        <button key={sl.slug} type="button"
          onClick={() => setActiveScale(sl.slug)}
          className="rounded-full px-2.5 py-1 text-[10px] font-semibold"
          style={{
            background: activeScale === sl.slug
              ? `color-mix(in srgb, ${color} 22%, transparent)`
              : "var(--border)",
            color: activeScale === sl.slug ? color : "var(--text-soft)",
            border: activeScale === sl.slug
              ? `1px solid color-mix(in srgb, ${color} 50%, transparent)`
              : "1px solid var(--border-strong)",
          }}
        >
          {sl.label}
        </button>
      );
    })}
  </div>
)}
```

**Add accordion** (same pattern as `AssignedWorkoutPanel`): two sections, default "Workout Details" expanded.

```typescript
const [activeSection, setActiveSection] = useState<"details" | "conversation">("details");
```

Accordion tabs bar:
```typescript
<div
  className="mt-4 grid grid-cols-2 rounded-2xl overflow-hidden"
  style={{ border: "1px solid var(--border)" }}
>
  {(["details", "conversation"] as const).map((tab) => (
    <button
      key={tab}
      type="button"
      onClick={() => setActiveSection(tab)}
      className="py-2.5 text-xs font-semibold capitalize"
      style={{
        background: activeSection === tab ? "var(--panel-muted)" : "var(--panel)",
        color: activeSection === tab ? "var(--text)" : "var(--dim)",
        borderBottom: activeSection === tab ? "2px solid var(--primary)" : "2px solid transparent",
      }}
    >
      {tab === "details" ? "Workout Details" : "Conversation"}
    </button>
  ))}
</div>
```

Accordion content:
```typescript
{activeSection === "details" && (
  <div className="mt-4">
    <WorkoutPreviewDetail
      sections={slot.workout?.sections ?? []}
      activeScaleOverride={activeScale}
    />
    {/* Booking status + cancel button (existing code, moved here) */}
    {slot.current_user_booking && <ExistingBookingStatus ... />}
    {canBook && <BookButton ... />}
  </div>
)}

{activeSection === "conversation" && (
  <div className="mt-4">
    {slot.current_user_booking ? (
      <ChatSection
        contextType="class_booking"
        contextId={slot.current_user_booking.id}
        accessToken={accessToken}
      />
    ) : (
      <p className="text-sm" style={{ color: "var(--dim)" }}>
        Book this class to start a conversation with the coach.
      </p>
    )}
  </div>
)}
```

- [ ] **Step 3: Verify messaging context supports `class_booking`**

Check `apps/api/lib/milos_training/messaging.ex` and the messaging channel for `class_booking` contextType. If not supported, note it as a prerequisite (backend must add it before this frontend step can be tested end-to-end).

- [ ] **Step 4: Commit**

```bash
git add apps/web/src/components/schedule/SlotPopup.tsx
git commit -m "feat(frontend/slot): member SlotPopup redesign — accordion, scale chips, pending banner, chat, remove info boxes"
```

---

## Task 10: Workout History — Grid/List Toggle + Filters

**Files:**
- Create: `apps/web/src/components/landing-page/WorkoutHistorySection.tsx`
- Modify: `apps/web/src/components/landing-page.tsx`

- [ ] **Step 1: Create `WorkoutHistorySection.tsx`**

```typescript
// apps/web/src/components/landing-page/WorkoutHistorySection.tsx
"use client";

import React, { useMemo, useState } from "react";
import type { WorkoutExecution } from "@/api/executions";

type ViewMode = "grid" | "list";

type Filters = {
  dateFrom: string;
  dateTo: string;
  workoutTypes: string[];
  hasModifications: boolean | null;
  status: "completed" | "in_progress" | null;
};

const WORKOUT_TYPES = ["crossfit", "strength", "gymnastics", "aerobics", "flexibility", "recovery"];

function ExecutionGridCard({
  execution,
  onClick,
}: {
  execution: WorkoutExecution;
  onClick: () => void;
}) {
  return (
    <button
      className="rounded-[1.5rem] px-4 py-4 text-left transition-transform hover:-translate-y-0.5"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
      onClick={onClick}
      type="button"
    >
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
        {execution.workout_title ?? "Workout"}
      </p>
      <p className="mt-1 text-xs uppercase tracking-[0.18em]" style={{ color: "var(--primary)" }}>
        {(execution.workout_type ?? "session").replace("_", " ")}
        {execution.scale_level_slug ? ` · ${execution.scale_level_slug}` : ""}
      </p>
      <p className="mt-3 text-sm" style={{ color: "var(--muted)" }}>
        {execution.completed_at_utc
          ? new Date(execution.completed_at_utc).toLocaleString()
          : "In progress"}
      </p>
      <p className="mt-2 text-xs" style={{ color: "var(--dim)" }}>
        {execution.exercise_notes.length} note{execution.exercise_notes.length !== 1 ? "s" : ""} ·{" "}
        {execution.section_scores.length} score{execution.section_scores.length !== 1 ? "s" : ""}
        {execution.exercise_modifications.length > 0 && (
          <span style={{ color: "var(--warning)" }}>
            {" "}· {execution.exercise_modifications.length} mod{execution.exercise_modifications.length !== 1 ? "s" : ""}
          </span>
        )}
      </p>
    </button>
  );
}

function ExecutionListCard({
  execution,
  onClick,
}: {
  execution: WorkoutExecution;
  onClick: () => void;
}) {
  return (
    <button
      className="flex items-center justify-between gap-4 rounded-[1.5rem] px-5 py-3.5 text-left transition-colors hover:brightness-105"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
      onClick={onClick}
      type="button"
    >
      <div className="min-w-0">
        <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {execution.workout_title ?? "Workout"}
        </p>
        <p className="text-xs" style={{ color: "var(--dim)" }}>
          {(execution.workout_type ?? "session").replace("_", " ")}
          {execution.scale_level_slug ? ` · ${execution.scale_level_slug}` : ""}
        </p>
      </div>
      <div className="shrink-0 text-right">
        <p className="text-xs" style={{ color: "var(--muted)" }}>
          {execution.completed_at_utc
            ? new Date(execution.completed_at_utc).toLocaleDateString()
            : "In progress"}
        </p>
        <div className="mt-0.5 flex items-center justify-end gap-2">
          {execution.section_scores.length > 0 && (
            <span className="text-[10px]" style={{ color: "var(--primary)" }}>
              {execution.section_scores.length} score{execution.section_scores.length !== 1 ? "s" : ""}
            </span>
          )}
          {execution.exercise_modifications.length > 0 && (
            <span className="text-[10px]" style={{ color: "var(--warning)" }}>
              {execution.exercise_modifications.length} mod{execution.exercise_modifications.length !== 1 ? "s" : ""}
            </span>
          )}
        </div>
      </div>
    </button>
  );
}

type Props = {
  executions: WorkoutExecution[];
  onSelectExecution: (id: string) => void;
};

export function WorkoutHistorySection({ executions, onSelectExecution }: Props) {
  const [viewMode, setViewMode] = useState<ViewMode>("grid");
  const [filtersOpen, setFiltersOpen] = useState(false);
  const [filters, setFilters] = useState<Filters>({
    dateFrom: "",
    dateTo: "",
    workoutTypes: [],
    hasModifications: null,
    status: null,
  });

  const activeFilterCount = [
    filters.dateFrom || filters.dateTo,
    filters.workoutTypes.length > 0,
    filters.hasModifications !== null,
    filters.status !== null,
  ].filter(Boolean).length;

  const filtered = useMemo(() => {
    return executions.filter((ex) => {
      if (filters.dateFrom && ex.completed_at_utc) {
        if (new Date(ex.completed_at_utc) < new Date(filters.dateFrom)) return false;
      }
      if (filters.dateTo && ex.completed_at_utc) {
        if (new Date(ex.completed_at_utc) > new Date(filters.dateTo + "T23:59:59Z")) return false;
      }
      if (filters.workoutTypes.length > 0 && !filters.workoutTypes.includes(ex.workout_type ?? "")) {
        return false;
      }
      if (filters.hasModifications === true && ex.exercise_modifications.length === 0) return false;
      if (filters.hasModifications === false && ex.exercise_modifications.length > 0) return false;
      if (filters.status === "completed" && !ex.completed_at_utc) return false;
      if (filters.status === "in_progress" && ex.completed_at_utc) return false;
      return true;
    });
  }, [executions, filters]);

  function clearFilters() {
    setFilters({
      dateFrom: "",
      dateTo: "",
      workoutTypes: [],
      hasModifications: null,
      status: null,
    });
  }

  function toggleWorkoutType(type: string) {
    setFilters((prev) => ({
      ...prev,
      workoutTypes: prev.workoutTypes.includes(type)
        ? prev.workoutTypes.filter((t) => t !== type)
        : [...prev.workoutTypes, type],
    }));
  }

  return (
    <section
      className="rounded-[2.2rem] p-6"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      {/* Header */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p
            className="text-sm font-semibold uppercase tracking-[0.24em]"
            style={{ color: "var(--dim)" }}
          >
            Workout history
          </p>
          <h2
            className="mt-1 text-2xl font-semibold tracking-tight"
            style={{ color: "var(--text)" }}
          >
            Recent completions
          </h2>
        </div>
        <div className="flex items-center gap-2">
          {/* View toggle */}
          <div
            className="flex overflow-hidden rounded-xl"
            style={{ border: "1px solid var(--border)" }}
          >
            {(["grid", "list"] as const).map((mode) => (
              <button
                key={mode}
                type="button"
                onClick={() => setViewMode(mode)}
                className="px-3 py-1.5 text-xs font-semibold"
                style={{
                  background: viewMode === mode ? "var(--primary)" : "var(--panel-muted)",
                  color: viewMode === mode ? "var(--bg)" : "var(--text-soft)",
                }}
              >
                {mode === "grid" ? "⊞ Grid" : "≡ List"}
              </button>
            ))}
          </div>

          {/* Filter button */}
          <button
            type="button"
            onClick={() => setFiltersOpen((v) => !v)}
            className="rounded-xl px-3 py-1.5 text-xs font-semibold"
            style={{
              background:
                activeFilterCount > 0
                  ? "color-mix(in srgb, var(--primary) 18%, transparent)"
                  : "var(--panel-muted)",
              color: activeFilterCount > 0 ? "var(--primary-strong)" : "var(--text-soft)",
              border: activeFilterCount > 0
                ? "1px solid color-mix(in srgb, var(--primary) 45%, transparent)"
                : "1px solid var(--border)",
            }}
          >
            Filters{activeFilterCount > 0 ? ` · ${activeFilterCount}` : ""}
          </button>
        </div>
      </div>

      {/* Filter panel */}
      {filtersOpen && (
        <div
          className="mt-4 rounded-[1.5rem] p-4 space-y-4"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
        >
          {/* Date range */}
          <div className="flex flex-wrap gap-3">
            <div>
              <label className="text-xs font-semibold" style={{ color: "var(--dim)" }}>From</label>
              <input
                type="date"
                value={filters.dateFrom}
                onChange={(e) => setFilters((prev) => ({ ...prev, dateFrom: e.target.value }))}
                className="mt-1 block rounded-xl px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
              />
            </div>
            <div>
              <label className="text-xs font-semibold" style={{ color: "var(--dim)" }}>To</label>
              <input
                type="date"
                value={filters.dateTo}
                onChange={(e) => setFilters((prev) => ({ ...prev, dateTo: e.target.value }))}
                className="mt-1 block rounded-xl px-3 py-2 text-sm outline-none"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
              />
            </div>
          </div>

          {/* Workout type multi-select */}
          <div>
            <p className="mb-2 text-xs font-semibold" style={{ color: "var(--dim)" }}>Type</p>
            <div className="flex flex-wrap gap-2">
              {WORKOUT_TYPES.map((type) => (
                <button
                  key={type}
                  type="button"
                  onClick={() => toggleWorkoutType(type)}
                  className="rounded-full px-3 py-1 text-xs font-semibold capitalize"
                  style={{
                    background: filters.workoutTypes.includes(type)
                      ? "color-mix(in srgb, var(--primary) 20%, transparent)"
                      : "var(--panel)",
                    color: filters.workoutTypes.includes(type)
                      ? "var(--primary-strong)"
                      : "var(--text-soft)",
                    border: filters.workoutTypes.includes(type)
                      ? "1px solid color-mix(in srgb, var(--primary) 45%, transparent)"
                      : "1px solid var(--border)",
                  }}
                >
                  {type}
                </button>
              ))}
            </div>
          </div>

          {/* Has modifications */}
          <div className="flex flex-wrap gap-2">
            <p className="w-full text-xs font-semibold" style={{ color: "var(--dim)" }}>
              Modifications
            </p>
            {([null, true, false] as const).map((val) => (
              <button
                key={String(val)}
                type="button"
                onClick={() => setFilters((prev) => ({ ...prev, hasModifications: val }))}
                className="rounded-full px-3 py-1 text-xs font-semibold"
                style={{
                  background:
                    filters.hasModifications === val
                      ? "color-mix(in srgb, var(--primary) 20%, transparent)"
                      : "var(--panel)",
                  color:
                    filters.hasModifications === val
                      ? "var(--primary-strong)"
                      : "var(--text-soft)",
                  border:
                    filters.hasModifications === val
                      ? "1px solid color-mix(in srgb, var(--primary) 45%, transparent)"
                      : "1px solid var(--border)",
                }}
              >
                {val === null ? "Any" : val ? "Has modifications" : "No modifications"}
              </button>
            ))}
          </div>

          {/* Status */}
          <div className="flex flex-wrap gap-2">
            <p className="w-full text-xs font-semibold" style={{ color: "var(--dim)" }}>Status</p>
            {([null, "completed", "in_progress"] as const).map((val) => (
              <button
                key={String(val)}
                type="button"
                onClick={() => setFilters((prev) => ({ ...prev, status: val }))}
                className="rounded-full px-3 py-1 text-xs font-semibold"
                style={{
                  background:
                    filters.status === val
                      ? "color-mix(in srgb, var(--primary) 20%, transparent)"
                      : "var(--panel)",
                  color: filters.status === val ? "var(--primary-strong)" : "var(--text-soft)",
                  border:
                    filters.status === val
                      ? "1px solid color-mix(in srgb, var(--primary) 45%, transparent)"
                      : "1px solid var(--border)",
                }}
              >
                {val === null ? "All" : val === "completed" ? "Completed" : "In Progress"}
              </button>
            ))}
          </div>

          {activeFilterCount > 0 && (
            <button
              type="button"
              onClick={clearFilters}
              className="text-xs font-semibold"
              style={{ color: "var(--danger)" }}
            >
              Clear all filters
            </button>
          )}
        </div>
      )}

      {/* Results */}
      <div className={`mt-5 ${viewMode === "grid" ? "grid gap-3 md:grid-cols-2 xl:grid-cols-3" : "space-y-2"}`}>
        {filtered.length === 0 ? (
          <div className="col-span-full">
            <p
              className="rounded-2xl px-4 py-5 text-sm"
              style={{ background: "var(--panel-muted)", color: "var(--dim)" }}
            >
              {activeFilterCount > 0
                ? "No workouts match your filters."
                : "Completed workouts will appear here once execution history starts building."}
            </p>
            {activeFilterCount > 0 && (
              <button
                type="button"
                onClick={clearFilters}
                className="mt-2 text-sm font-semibold"
                style={{ color: "var(--primary)" }}
              >
                Clear filters
              </button>
            )}
          </div>
        ) : viewMode === "grid" ? (
          filtered.map((ex) => (
            <ExecutionGridCard
              key={ex.id}
              execution={ex}
              onClick={() => onSelectExecution(ex.id)}
            />
          ))
        ) : (
          filtered.map((ex) => (
            <ExecutionListCard
              key={ex.id}
              execution={ex}
              onClick={() => onSelectExecution(ex.id)}
            />
          ))
        )}
      </div>
    </section>
  );
}
```

- [ ] **Step 2: Replace inline workout history in `landing-page.tsx`**

```typescript
import { WorkoutHistorySection } from "@/components/landing-page/WorkoutHistorySection";

// Replace the existing inline workout history section with:
{!isAdmin && (
  <WorkoutHistorySection
    executions={landing.recent_executions}
    onSelectExecution={setSelectedExecutionId}
  />
)}
```

Remove the old inline workout history section.

- [ ] **Step 3: Commit**

```bash
git add apps/web/src/components/landing-page/WorkoutHistorySection.tsx apps/web/src/components/landing-page.tsx
git commit -m "feat(frontend/history): workout history grid/list toggle + date/type/modification/status filters"
```

---

## Task 11: End-to-End Verification

- [ ] **Step 1: Start dev server and verify each feature area**

```bash
cd apps/web && npx next dev
```

Verify in browser:

**Profile — Training Schedule:**
- Navigate to `/profile`, open "Training Schedule"
- Select 3 days, attempt 4th — blocked
- Save, reload — selection persists
- 0 days = valid ("I train every day")

**Landing page:**
- When `preferences === null`: yellow banner appears above stats strip
- Banner disappears after saving preferences
- Hero shows `"Good {morning|afternoon|evening}, {nickname}!"` + dynamic second line
- Stats strip shows 4 cards: Motivation%, Consistency days, Perseverance%, Advancement count
- ⚙ on Consistency opens ConsistencyInfoModal with link to Profile

**Pantheon — Landing section:**
- Add PR via "+ Add PR" button
- PR card shows: name, score with unit, date, ↑/↓ icon (subtle, with hover tooltip)
- "History ▾" expands with past entries
- "Share →" copies formatted message to modal
- "Edit" opens pre-filled modal
- "✕" confirms then deletes
- Search filters cards in real-time (debounced)
- "View all →" appears when >5 PRs

**Pantheon — Full page `/my-workouts/pantheon`:**
- All PRs visible, scrollable, newest first
- Same card UI as landing section
- "+ Add PR" button works

**Execution — Modify step:**
- Start a workout, each checklist step has "Modify this step" link
- Click opens modal with pre-filled fields
- Save logs modification; step shows "✎ Modified"

**Execution — 3-step wizard:**
- Complete workout → wizard opens (not old `CompletionReview`)
- Step 1: scores editable
- "Skip" and "Next →" both advance
- Step 2: pre-populated modifications, "✕" removes entries
- Step 3: summary + "Save & Done" → saves with modifications

**Creation — Notes:**
- In canvas, each section has a note textarea below exercises
- Each exercise has a small note input beneath name
- Notes appear in WorkoutPreviewDetail (italic, muted)

**Creation — Hotkeys:**
- `?` button in top-right → shortcuts modal
- `Alt+S` → adds new section (not in input/textarea)
- `Alt+/` → opens shortcuts modal
- `Alt+E` → adds exercise to active section
- Typing in title input does not trigger hotkeys

**SlotPopup — Member view:**
- Click a class slot as a member
- No capacity / approval / deadline info boxes
- Scale chips appear below workout title in sticky header
- Accordion tabs: "Workout Details" / "Conversation"
- Default: Workout Details expanded
- Conversation shows ChatSection when booking exists
- Pending banner visible when booking status is "pending" and slot is not auto-approve

**Workout history:**
- ⊞ Grid / ≡ List toggle switches layout
- Filter button opens filter panel
- Date range filtering works
- Workout type multi-select filters work
- "Has modifications" toggle filters
- Status filter works
- Active filter count shown on button
- Empty state shows "No workouts match your filters." + "Clear filters"

- [ ] **Step 2: Fix any TypeScript errors**

```bash
cd apps/web && npx tsc --noEmit
```

Fix all type errors before committing.

- [ ] **Step 3: Final commit**

```bash
git add -u
git commit -m "feat(frontend): end-to-end verification pass — all 6 feature areas working"
```
