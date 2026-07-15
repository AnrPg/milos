# Spec: UI Improvements — Admin Workout Panel, Stats Messages, Badge Tooltips, History Filters
**Date:** 2026-06-16
**Status:** Approved — ready for implementation

---

## Overview

Five targeted UI improvements across the admin workout console and the member landing page:

1. **Admin workout side panel** — clicking a workout opens a slide-in preview panel
2. **NaN% stats → insightful messages** — replace NaN with contextual copy; show off-days banner when no off-days configured
3. **Badge chips: full label + hover tooltip** — show complete milestone name and on-hover description
4. **Workout history: date range picker + all known types** — custom date picker + show all types (muted if no data)
5. **PR creation bug fix** — atom/string key mismatch in `create_pr.ex`

---

## 1. Admin Workout Side Panel

**Component:** `WorkoutAdminConsole.tsx`

### Behaviour
- Workout cards remain clickable for actions (Assign, Edit, Delete buttons work normally)
- The card itself (title area) is wrapped in a clickable zone that sets `previewWorkoutId`
- A fixed slide-in overlay panel appears from the right (width: `min(480px, 90vw)`) showing the workout preview
- Panel header: workout title + type badge + Close button
- Panel body: `<WorkoutPreviewDetail sections={workout.sections} />` directly (data already in `WorkoutRecord`)
- Close on: Escape key, clicking backdrop, clicking Close button

### State additions to `WorkoutAdminConsole`
```tsx
const [previewWorkoutId, setPreviewWorkoutId] = useState<string | null>(null);
const previewWorkout = workouts.find((w) => w.id === previewWorkoutId) ?? null;
```

### Panel structure
```
┌─ backdrop ─────────────────────────────────────────────┐
│                            ┌─ slide panel ────────────┤
│                            │  [TITLE]    [type badge]  │
│                            │  ─────────────────────── │
│                            │  <WorkoutPreviewDetail /> │
│                            │                           │
│                            │             [Close]       │
└────────────────────────────└───────────────────────────┘
```

No separate fetch needed — `WorkoutRecord.sections` already contains the exercise data.

---

## 2. NaN% Stats → Insightful Messages

**Component:** `landing-page.tsx` stats strip + `OffDaysBanner`

### Stats strip guard
Replace `{Math.round(stats.motivation_score)}%` with helper:

```tsx
function statDisplay(score: number | null | undefined, totalWorkouts: number, weeklyTarget: number, kind: "motivation" | "perseverance"): string {
  const rounded = Math.round(score ?? NaN);
  if (!isNaN(rounded)) return `${rounded}%`;
  if (totalWorkouts === 0) return "No workouts yet";
  if (kind === "motivation" && weeklyTarget === 0) return "Set a weekly target";
  return "Calculating…";
}
```

- **Motivation NaN**: `total_workouts === 0` → "No workouts yet"; `weekly_workout_target === 0` → "Set a weekly target"; else → "Calculating…"
- **Perseverance NaN**: `total_workouts === 0` → "No workouts yet"; else → "Calculating…"

### OffDaysBanner extension
Current: only shows when today is in off_days.
New: **also** shows (different message) when `offDays.length === 0` AND `preferences` is non-null.

When `preferences === null` (never configured): show "Set your rest days" banner (already exists in spec).
When `offDays.length === 0` (configured but empty = trains every day): no banner needed.
When `offDays.includes(todayDow)`: show rest day banner (existing).

**Key change:** Show the NaN-explaining message inline under each stat card when score is NaN, not in the banner. The banner is only for the rest-day reminder.

For NaN motivation specifically: if the cause is no off-days set, also display the banner nudging user to configure preferences.

---

## 3. Badge Chips: Full Label + Hover Tooltip

**Component:** `landing-page.tsx` → `MemberHero`

### Current
```tsx
<span>{badge.firstWord}</span>  // only first word of label
```

### New
```tsx
<span>{badge.label}</span>  // full label (e.g. "10 Workouts")
```

### Tooltip (title attribute)
Add `title={getBadgeDescription(badge.badge_key)}` on the chip wrapper div.

### `getBadgeDescription` helper
```tsx
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
```

---

## 4. Workout History: Date Range Picker + All Known Types

**Component:** `landing-page.tsx` workout history section

### Date filter changes

Keep existing "All time / This week / This month / Last month" preset chips.

**Add:** Two `<input type="date">` inputs (From / To) for custom range.
- When either is set, it overrides the preset chips (presets become inactive / visual only)
- Clear button clears both custom dates and reverts to "All time"
- Date inputs are rendered inline alongside preset chips with a separator

### Type filter changes

**Current:** `allTypes` derived from `landing.recent_executions` — only types that exist in data.

**New:** Show all known types always:
```tsx
const KNOWN_TYPES = ["crossfit", "strength", "gymnastics", "aerobics", "flexibility", "recovery", "session"];
```

For each type:
- **Has data** (`landing.recent_executions.some(e => (e.workout_type ?? "session") === t)`): normal style, clickable
- **No data for type**: muted color (`var(--dim)`), lower opacity, `cursor: not-allowed`, `disabled` state, `title="No workouts of this type"`

Preset date chips (This week, This month, Last month) also become muted/disabled if no executions fall in that date range.

---

## 5. PR Creation Bug Fix

**File:** `apps/api/lib/milos_training/application/create_pr.ex`

**Line 8:** `Map.put(params, :user_id, user_id)` uses an atom key `:user_id` on a string-keyed map.

**Fix:** Change to `Map.put(params, "user_id", user_id)` — consistent with all other string keys in the params map coming from controller parsing.

---

## Implementation Order

1. Fix PR creation bug (`create_pr.ex`) — 1 line
2. Admin workout side panel (`WorkoutAdminConsole.tsx`) — new panel component
3. Badge chips (`landing-page.tsx` `MemberHero`) — helper + label change
4. Stats NaN messages (`landing-page.tsx` stats strip)
5. Date picker + all types filter (`landing-page.tsx` history section)
