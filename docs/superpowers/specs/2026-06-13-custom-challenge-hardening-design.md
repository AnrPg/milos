# Custom Challenge Hardening — Design Spec
Date: 2026-06-13
Status: Approved

## Overview

Harden the `custom` criteria type for seasonal challenges end-to-end:
fix a landing-page target computation bug, expose increment semantics to
athletes, add a per-challenge opt-in Hall of Fame leaderboard (expandable
inline on the landing page), and improve the admin form and participant table.

---

## 1. Data Model Changes

### 1a. `criteria_value` for `custom` type — add `increment_label`

`criteria_value` for `custom` challenges gains an optional `increment_label`
string field:

```json
{
  "count": 20,
  "increment_per_completion": 5,
  "increment_label": "for improving weekly consistency"
}
```

- `increment_label` is optional. If absent, no reason text is shown.
- Validated and stored by `ChallengeCriteria.normalize_value("custom", …)`.
- `ChallengeCriteria.increment_label/1` extractor helper (returns `nil` when absent).

### 1b. `user_challenge_progress` — add `last_increment_event`

New nullable JSONB column `last_increment_event`:

```json
{ "points": 5, "label": "for improving weekly consistency" }
```

Set on every `upsert_user_challenge_progress` call that results in a positive
increment. Persists across page reloads — this is the "last points earned"
message shown to the athlete until overwritten by the next progress step.

Migration: `add :last_increment_event, :map, default: nil`

### 1c. `challenge_leaderboard_opt_ins` — new table

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `user_id` | uuid FK → users | |
| `challenge_id` | uuid FK → seasonal_challenges ON DELETE CASCADE | |
| `inserted_at` | utc_datetime_usec | |

Unique index: `(user_id, challenge_id)`.

Default: users are **opted-out**. A row in this table means opted-in.

---

## 2. Domain Layer Changes

### `ChallengeCriteria`

- `normalize_value("custom", count, value)`: also accept optional `"increment_label"` string ≤ 160 chars; include it in the normalized map if present.
- New helper: `increment_label(%{criteria_value: cv})` → `cv["increment_label"]` | `nil`

### `ChallengeProgress`

No changes. `increment/2` already works correctly for `custom` type.

### New: `ChallengeLeaderboard` domain (pure functions)

```elixir
defmodule MilosTraining.Gamification.Domain.ChallengeLeaderboard do
  # Compute display rank for a list of opted-in participant maps
  def rank(participants)  # → sorted list with :rank field added
end
```

---

## 3. Application Layer Changes

### `GetLandingPage`

**Bug fix**: replace raw `Map.get(challenge.criteria_value, "count")` with
`ChallengeProgress.target(challenge)`.

**New payload fields per challenge**:

```elixir
%{
  # existing
  id, title, description, badge_key, badge_label,
  criteria_type, target, progress, completed_at, completed,
  starts_at, ends_at,
  # new
  increment_per_completion: integer | nil,   # custom type only
  increment_label: string | nil,             # custom type only
  completions_remaining: integer,            # max(0, ceil((target-progress)/inc)) for custom, else max(0, target-progress)
  is_opted_in: boolean,                      # Hall of Fame opt-in status
  last_progress_event: %{points: integer, label: string | nil} | nil
}
```

### `RecordWorkoutCompletion`

Return value extended:

```elixir
{:ok, %{
  challenge_completions: [...],   # existing: challenges just reached
  challenge_increments: [         # new: every challenge that got non-zero progress
    %{challenge_id: id, title: title, points: integer, label: string | nil}
  ]
}}
```

Internal change in `persist_challenge_progress/5`:
- Check opt-in status for each (user_id, challenge_id) pair.
- If **opted-out**: `next_progress = min(update.progress, target)` — cap at target.
- If **opted-in**: `next_progress = update.progress` — accumulates past target.
- Pass `last_increment_event` map to `upsert_user_challenge_progress` when
  `increment > 0`.

### `CompleteWorkout`

`process_completion/1` broadcasts `challenge_increments` after success:

```elixir
BroadcastUserSync.for_user(user_id, ["landing"],
  reason: "challenge_progress_advanced",
  payload: %{increments: challenge_increments}
)
```

### New: `OptInChallengeLeaderboard` / `OptOutChallengeLeaderboard`

```elixir
OptInChallengeLeaderboard.call(user_id, challenge_id) → :ok | {:error, _}
OptOutChallengeLeaderboard.call(user_id, challenge_id) → :ok
```

### New: `GetChallengeLeaderboard`

```elixir
GetChallengeLeaderboard.call(challenge_id, requesting_user_id) →
  {:ok, %{participants: [...], challenge: %{...}}}
```

Returns top-50 opted-in participants sorted by `progress desc`, with the
requesting user's row highlighted even if outside top 50.

### `GetAdminChallenge`

Participant rows gain two new fields (custom challenges only):

```elixir
%{
  ...existing fields...,
  completions_done: floor(progress / increment_per_completion) | nil,
  completions_remaining: ceil((target - progress) / increment_per_completion) | nil
}
```

---

## 4. Infrastructure Layer

### `GamificationStore` port — new callbacks

```elixir
@callback opt_in_leaderboard(user_id :: Ecto.UUID.t(), challenge_id :: Ecto.UUID.t()) ::
            {:ok, any()} | {:error, Ecto.Changeset.t()}

@callback opt_out_leaderboard(user_id :: Ecto.UUID.t(), challenge_id :: Ecto.UUID.t()) :: :ok

@callback leaderboard_opt_in?(user_id :: Ecto.UUID.t(), challenge_id :: Ecto.UUID.t()) :: boolean()

@callback list_leaderboard_participants(challenge_id :: Ecto.UUID.t()) ::
            list(map())
```

### `EctoGamificationStore` — changes

- Implement the four new callbacks above.
- `upsert_user_challenge_progress/1`: accept `:last_increment_event` in params and persist it.
- `normalize_challenge/1`: expose `increment_label` extracted from `criteria_value`.

### New schema: `ChallengeLeaderboardOptIn`

```elixir
schema "challenge_leaderboard_opt_ins" do
  field :user_id, :binary_id
  field :challenge_id, :binary_id
  timestamps(updated_at: false)
end
```

---

## 5. API Layer

### New routes (athlete-facing)

```
POST   /challenges/:id/opt_in      → ChallengeController.opt_in
DELETE /challenges/:id/opt_in      → ChallengeController.opt_out
GET    /challenges/:id/leaderboard → ChallengeController.leaderboard
```

Protected by `require_authenticated_user` plug.

### New `ChallengeController`

Three actions. Leaderboard response shape:

```json
{
  "leaderboard": [
    { "rank": 1, "nickname": "Maria", "progress": 35, "target": 20, "completed_at": "..." }
  ],
  "my_rank": 3,
  "my_progress": 15
}
```

---

## 6. Frontend Changes

### `apps/web/src/api/challenges.ts`

New functions:
- `optInChallenge(token, challengeId)`
- `optOutChallenge(token, challengeId)`
- `fetchChallengeLeaderboard(token, challengeId)`

New types:
- `ChallengeLeaderboardEntry`
- `LandingChallengeRecord` (typed version of enriched landing payload)

### `RealtimeSyncBridge`

Handle reason `"challenge_progress_advanced"` in the `sync:refresh` handler:

```ts
case "challenge_progress_advanced":
  // Store increments in a Map<challengeId, {points, label}>
  // Dispatch USER_SYNC_EVENT with scope "challenge_increments" + payload
  break;
```

The `challenge_progress_advanced` reason triggers standard `["landing"]` query
invalidation — no separate local `lastIncrements` state needed. On refetch,
the landing payload already carries the updated `last_progress_event` from DB.

### Landing page challenge card

Expandable card design (collapsed by default):

```
┌─────────────────────────────────────────────────────┐
│ Weekly Grind                       [Target Reached!] │  ← badge if completed
│ Progress: 3/20 pts · 1 completion to go             │  ← completions_remaining
│ You gained +5 pts for improving weekly consistency  │  ← last_progress_event
│                                                     │
│ [Join Hall of Fame]  ↓ View leaderboard             │  ← opt-in toggle + expand
└─────────────────────────────────────────────────────┘

[expanded]
├─────────────────────────────────────────────────────┤
│ 🏆 Hall of Fame                                     │
│  1. Maria    35 pts ██████████                      │
│  2. Alex     20 pts ██████                          │
│  3. You      15 pts ████         ← highlighted      │
└─────────────────────────────────────────────────────┘
```

State when opted-out:
- Progress bar / badge show normally.
- When target reached: "Target reached! 🎉" badge, no leaderboard shown, no further progress accumulation shown past target.
- "Join Hall of Fame" CTA visible.

State when opted-in + target reached:
- "Target reached! 🎉" badge remains.
- Progress continues incrementing visually (e.g., "25/20 pts").
- Leaderboard expandable.

The `last_progress_event` text is rendered as-is from the DB value (persists
across reloads). Overwritten on next sync event with reason
`challenge_progress_advanced`.

### `admin-challenges.tsx`

- `criteriaSummary` for custom type:
  - No label: `"Reach N pts (+M per completion)"`
  - With label: `"Reach N pts (earn points M per completion)"`
- Add optional "Points label" text input for custom type.
- Add `min={1}` and `step={1}` to `incrementPerCompletion` input.
- Participant table: for custom challenges, add "Done" and "Remaining" columns
  (showing `completions_done` / `completions_remaining` from the API).

---

## 7. Realtime Flow

```
Athlete completes workout
  → RecordWorkoutCompletion (backend)
  → persist_challenge_progress: checks opt-in per challenge
  → upsert_user_challenge_progress (persists last_increment_event, respects cap)
  → returns challenge_increments
  → CompleteWorkout.process_completion
  → BroadcastUserSync(["landing"], reason: "challenge_progress_advanced", payload: increments)
  → RealtimeSyncBridge receives sync:refresh
  → invalidates ["landing"] React Query cache
  → LandingPage refetch → landing payload now has updated last_progress_event
  → LandingPage re-renders with new progress + new "You gained..." text
```

---

## 8. Out of Scope

- Dynamic per-completion reason text (e.g., "for breaking a PR") — `increment_label` is static, set by admin. Dynamic reasons require a different criteria subtype.
- Per-challenge notification throttling.
- Hall of Fame pagination beyond top 50.
- Admin ability to see or manage opt-in lists.
