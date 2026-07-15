# Spec: Gamification Redesign, Pantheon, Modification Tracking, Workout Creation & Panel Improvements
**Date:** 2026-06-16
**Status:** Approved — ready for implementation planning

---

## Overview

Six interconnected feature areas:

1. **Gamification metrics redesign** — 4 new metrics (Motivation, Consistency, Perseverance, Advancement) replacing the current badge chips; off-days setting across all hexagonal layers
2. **Pantheon** — Hall of Fame PR tracking system (landing page section + full page)
3. **Workout modification tracking** — structured per-exercise modifications during execution + 3-step finish wizard
4. **Workout creation improvements** — hotkeys (Alt+letter) + coach notes on sections/exercises
5. **SlotPopup member redesign** — accordion pattern, scale chips, chat thread, remove capacity/confirmation UI
6. **Workout history** — grid/list toggle + date/type/modifications/status filters

---

## 1. Gamification Metrics Redesign

### 1.1 Four New Metrics

| Metric | Definition | Field in `user_stats` |
|--------|-----------|----------------------|
| **Motivation** | % of last 10 weeks where workouts ≥ `weekly_workout_target` | `motivation_score: float` |
| **Consistency** | Consecutive training days streak; off-days (max 3/week, user-set) don't break it | `current_streak: integer` (now days, not weeks) |
| **Perseverance** | For last 7 training days (excl. off-days): avg `(1 − deviation_ratio)` per exercise | `perseverance_score: float` |
| **Advancement** | Count of Pantheon PR improvement events | `advancement_count: integer` |

`longest_streak` changes semantic meaning from weeks to days. Migration zeroes existing values.

### 1.2 Perseverance Deviation Rules

- **Skipped exercise:** deviation = `sets × prescribed_reps`
- **Skipped set:** deviation = `sum of reps of all exercises in that set`
- **Time field:** `|prescribed_mins − actual_mins| / prescribed_mins`
- **Other numeric field:** `|prescribed − actual| / prescribed`
- **No modification logged:** deviation = 0
- Final score per day = `mean(1 − deviation_i)` across all exercises that day
- Perseverance = mean of daily scores over last 7 training days (off-days excluded)

### 1.3 Domain Layer — New Pure Calculators

All calculators receive `off_days: [integer]` as explicit parameter (zero DB coupling):

- `MilosTraining.Gamification.Domain.MotivationCalculator` — pure function, takes `completed_dates`, `target`, `off_days`
- `MilosTraining.Gamification.Domain.DayStreakCalculator` — replaces weekly logic; takes `completed_dates`, `off_days`, `current_date`
- `MilosTraining.Gamification.Domain.PerseveranceCalculator` — takes `exercise_modifications`, `workout_prescriptions`, `off_days`

### 1.4 Off-Days Setting — Full Hexagonal Stack

**Schema — new table `user_gamification_preferences`:**
```sql
id            uuid PRIMARY KEY
user_id       uuid UNIQUE NOT NULL REFERENCES users(id)
off_days      integer[]   -- values 0..6 (0=Sun, 1=Mon … 6=Sat), max 3
inserted_at   timestamptz
updated_at    timestamptz
```

**Port additions to `GamificationStore`:**
```elixir
@callback get_user_preferences(user_id :: binary()) :: map() | nil
@callback upsert_user_preferences(user_id :: binary(), params :: map()) ::
            {:ok, map()} | {:error, Ecto.Changeset.t()}
```

**Application layer:**
- `GetGamificationPreferences` — query, returns preferences or nil
- `UpdateGamificationPreferences` — validates `off_days` (max 3, values 0–6, unique); triggers streak recalculation on change

**API:**
```
GET  /api/gamification/preferences
PUT  /api/gamification/preferences   body: { off_days: [1, 6] }
```

**Infrastructure:** `EctoGamificationStore` implements both callbacks via `Repo.insert_or_update` on `UserGamificationPreferences` changeset.

**Frontend — Profile page surface:**
New section in `/profile`: "Training Schedule". Seven day checkboxes (Mon–Sun), max 3 selectable. Save button. Caption: *"Selected days are excluded from your streak and perseverance calculations — so a rest day won't break your progress."*

**Frontend — Landing page warning (when preferences === null):**
Prominent info banner above stats strip, visible only when `gamification.preferences === null`:
> ⚠️ **Set your rest days for accurate metrics**
> Your Consistency, Perseverance and Motivation scores exclude your scheduled rest days — but we don't know which days those are yet. Without this, your streak may break on days you never planned to train.
> → [Set your rest days in Profile]

Banner disappears once preferences are saved (empty array = "I train every day" is valid and clears the warning).

### 1.5 Schema Additions to `user_stats`

```elixir
field :motivation_score,   :float,   default: 0.0
field :perseverance_score, :float,   default: 0.0
field :advancement_count,  :integer, default: 0
# current_streak / longest_streak: now in DAYS (was weeks — migration zeroes existing values)
```

### 1.6 Hero + Stats Strip Changes

**Hero (`MemberHero`):**
- Remove all badge/milestone chips
- Remove streak chip
- Add personalized welcome message as first element: `"Good {morning|afternoon|evening}, {nickname}!"` + dynamic second line based on data (e.g., `"You're on a 12-day streak."` or `"Last trained 3 days ago. Let's go."`)
- Quote block remains below the welcome message

**Stats strip — 4 cards (replace existing 3):**

| Card | Value | Subtitle | Extra |
|------|-------|---------|-------|
| Motivation | `{motivation_score}%` | Last 10 weeks on target | — |
| Consistency | `{current_streak} days` | Longest: {longest_streak} days | ⚙ icon → off-days popover (link to Profile) |
| Perseverance | `{perseverance_score}%` | Last 7 training days | — |
| Advancement | `{advancement_count}` | Pantheon PRs beaten | — |

The ⚙ on the Consistency card opens a small popover with a link to the Profile "Training Schedule" section (does not duplicate the setting inline — Profile is the single source).

---

## 2. Pantheon (PR Hall of Fame)

### 2.1 Naming

Feature is called **Pantheon** everywhere: routes, UI labels, API paths, Elixir module names.

### 2.2 Placement

- **Landing page:** Block section below workout history — shows up to 5 most recent PRs as cards, search bar, "View all →" link
- **Full page:** `/my-workouts/pantheon` — all PRs, scrollable, no pagination, newest first

### 2.3 Schema

```sql
-- user_pr_records
id               uuid PRIMARY KEY
user_id          uuid NOT NULL REFERENCES users(id)
name             text NOT NULL              -- free text PR title e.g. "Back Squat"
current_score    numeric NOT NULL
unit             text NOT NULL              -- 'mins_secs' | 'reps' | 'sets' | 'kcals' | 'm' | 'kg'
higher_is_better boolean NOT NULL DEFAULT true
beaten_on        date NOT NULL DEFAULT CURRENT_DATE
inserted_at      timestamptz
updated_at       timestamptz

-- user_pr_history
id               uuid PRIMARY KEY
pr_record_id     uuid NOT NULL REFERENCES user_pr_records(id) ON DELETE CASCADE
score            numeric NOT NULL
beaten_on        date NOT NULL
inserted_at      timestamptz
```

`UPDATE` on `user_pr_records` automatically inserts a `user_pr_history` row (via application layer, not DB trigger). `advancement_count` in `user_stats` increments when a new PR record is created OR when an update sets a score better than the previous.

### 2.4 Meilisearch Integration

Index name: `user_pr_records`. Filterable attribute: `user_id`. Searchable attribute: `name`. Sync via Oban job on create/update/delete (existing pattern). Every search query includes `filter: "user_id = {current_user_id}"`.

### 2.5 API Endpoints

```
GET    /api/prs                  list (+ ?q= for search)
POST   /api/prs                  create
PATCH  /api/prs/:id              update (auto-logs to history, updates advancement_count)
DELETE /api/prs/:id              delete (cascades history)
GET    /api/prs/:id/history      full chronological history
POST   /api/prs/:id/share        returns formatted DM message string
```

**Share message format:** `"🏆 New PR — {name}: {score} {unit} (beaten on {date})"`

### 2.6 Card Design

Each PR is rendered as a card (not a table row):

```
┌─────────────────────────────────────────────┐
│  BACK SQUAT                        Jun 15   │
│                                             │
│       142.5 kg                        ↑     │
│                                             │
│  [History ▾]         [Share →]  [Edit] [✕] │
└─────────────────────────────────────────────┘
```

- Score: large, prominent, unit inline
- `↑` / `↓`: tiny icon, `var(--dim)` color, top-right corner of score area. Hover tooltip: "Higher score is better" / "Lower score is better". No text label.
- "History ▾": expands inline showing past scores chronologically, each as `{score} {unit} — {date}`
- Card accent color: based on unit (consistent mapping across all cards)
- Search bar above cards, debounced

### 2.7 Add/Edit Modal

Fields: Name (text), Score (number), Unit (select dropdown), Higher is better (boolean toggle: "Higher / Lower is better"), Date (date picker, default today).

---

## 3. Workout Modification Tracking

### 3.1 Schema Addition to `workout_executions`

```elixir
field :exercise_modifications, {:array, :map}, default: []
```

Each entry map:
```elixir
%{
  exercise_id:       String.t(),
  step_label:        String.t(),      # human-readable, e.g. "Section 2 · Back Squat"
  field:             String.t(),      # "reps" | "sets" | "kg" | "kcal" | "time_mins" | "distance_m"
  prescribed_value:  float(),
  actual_value:      float() | nil,
  skipped:           boolean(),
  logged_at:         DateTime.t()
}
```

### 3.2 During Execution UI

Each active execution step has a **"Modify this step"** button (subtle, secondary style — not prominent).

Click → small modal:
- Pre-filled editable fields matching the step's prescription (reps, sets, kg, kcal, time, distance — only fields relevant to the step's format)
- Checkbox: "Skipped entirely" — when checked, greys out value fields
- Save → appends entry to `exercise_modifications` (optimistic update + debounced background sync)
- Modal closes; step shows subtle "modified" indicator (small dot or icon)

### 3.3 Three-Step Finish Wizard

Replaces/extends the existing score submission flow. All steps are skippable.

**Step 1 — Scores** (existing, minimal changes):
- Review and edit section scores
- Skip button → jump to Step 2

**Step 2 — Modifications:**
- Pre-populated from in-workout logged modifications
- "Add another modification" → step selector dropdown → same edit modal
- Edit or delete existing modifications
- Skip button → jump to Step 3

**Step 3 — Review** (existing):
- Optional workout review submission
- Skip / Finish button

### 3.4 Coach/Admin Modifications

In the admin athlete drill-down for a specific execution: new "Modifications" tab. Coach can view existing modifications and add new ones using the same modal format.

**New endpoint:** `POST /api/executions/:id/modifications` — admin/coach only. Accepts array of modification entries, merges with existing `exercise_modifications`.

Coach modifications are included in perseverance calculations identically to user self-modifications.

---

## 4. Workout Creation — Hotkeys + Coach Notes

### 4.1 Coach Notes Schema

```elixir
# workout_sections table
field :note, :string   # coaching cue displayed after section exercises

# workout_exercises table
field :note, :string   # coaching cue displayed next to exercise name
```

Notes are:
- Written only by workout creators (admin/coach) at creation time
- Readonly for athletes during preview and execution
- Display: italic, muted style, clearly distinguished from exercise data
- Section note: below the section's exercises in preview/execution
- Exercise note: beneath exercise name, small font

### 4.2 Hotkey Bindings

Implemented as `keydown` listener in `WorkoutCreationCanvas` `useEffect`. Guard: `if (document.activeElement instanceof HTMLInputElement || document.activeElement instanceof HTMLTextAreaElement) return;`

| Hotkey | Action | Context required |
|--------|--------|-----------------|
| `Alt+E` | Add exercise to active section | Active section selected |
| `Alt+S` | Add new section | Always |
| `Alt+V` | Add variations to selected exercise | Exercise selected |
| `Alt+A` | Open advanced settings for selected exercise | Exercise selected |
| `Alt+P` | Set progressive load for selected exercise | Exercise selected |
| `Alt+N` | Add/focus note for selected section or exercise | Section or exercise selected |
| `Alt+K` | Duplicate selected section | Section selected |
| `Alt+/` | Toggle shortcuts modal | Always |
| `Escape` | Close open panels/modals | Always |
| `Tab` / `Shift+Tab` | Navigate between exercises | Canvas focused, not in input |
| `Backspace` | Delete selected exercise (confirm if has data) | Exercise selected |

If context not met (e.g., Alt+E with no section): subtle shake animation + tooltip "Select a section first."

`Alt+D` deliberately avoided — conflicts with browser address bar focus in Chrome/Edge.

### 4.3 Hotkey Display

**Tooltip hints:** Every action button shows hotkey in tooltip on hover. Example: `"Add Exercise (Alt+E)"`.

**Shortcuts modal:** Subtle `?` button in `CanvasHeader` top-right corner. Opens modal with shortcuts in three columns:

```
Section Actions          Exercise Actions         Navigation
────────────────         ────────────────         ──────────
Alt+S  New section       Alt+E  Add exercise      Tab      Next exercise
Alt+K  Duplicate         Alt+V  Variations        ⇧Tab     Prev exercise
Alt+N  Section note      Alt+A  Advanced          Esc      Close panel
                         Alt+P  Progressive load
                         Alt+N  Exercise note
                         Alt+/  This help
                         ⌫      Delete exercise
```

---

## 5. SlotPopup — Member View Redesign

### 5.1 Removed Elements (non-admin view)

- "Capacity" info box (`approved_booking_count / capacity`) — remains visible in calendar card only
- "Participation approval" info box ("Auto-confirmed" / "By coach")
- "Deadline to book" info box

### 5.2 Pending Booking Banner

Shown when `!slot.auto_approve && slot.current_user_booking?.status === "pending"`:

> *"Your booking is pending approval by the class's coach. He has been notified — please wait a while."*

Styled as subtle info banner with `var(--warning)` color. Not an error state.

### 5.3 Scale Chips

Extracted from workout section details and placed in the sticky header, directly below the workout title. One chip per scale level + "Base" chip. Color-coded by index (consistent, not per-slug):

```
index 0 (Base):   var(--primary)
index 1:          var(--warning)
index 2:          var(--success)
index 3:          #a78bfa  (violet)
index 4+:         var(--dim)
```

Active chip = filled background. Inactive = outlined border only. Clicking a chip sets `activeScale` state, passing it to `WorkoutPreviewDetail` as `activeScaleOverride`.

### 5.4 Accordion Structure

Two sections, collapsible, only one expanded at a time (same pattern as `AssignedWorkoutPanel`). Default: Workout Details expanded.

**"Workout Details"** (default expanded):
- `WorkoutPreviewDetail` with `activeScaleOverride`
- Coach/admin note (if present)
- Booking status + Cancel booking button
- Reschedule option (if permitted)

**"Conversation"** (collapsed by default):
- `ChatSection` with `contextType="class_booking"`, `contextId={slot.current_user_booking.id}`
- Private thread between member and class creator (admin)
- Only rendered when `slot.current_user_booking` exists
- If no booking yet: accordion section is disabled with tooltip "Book this class to start a conversation"

### 5.5 Backend Requirement

Verify `contextType: "class_booking"` is supported in the Messaging bounded context. If not, add it before frontend implementation.

---

## 6. Workout History — View Toggle + Filters

### 6.1 View Toggle

Two chips in the "Workout history" section header:
- `⊞ Grid` (default — existing 2–3 column card layout)
- `≡ List` — single column; each execution as a wider card showing: workout title, type, date, score count, modifications badge — all inline for quick scanning

### 6.2 Filters

Filter button next to chips shows active filter count badge (e.g., `Filters · 2`).

Click → dropdown/panel with:

| Filter | Type | Implementation |
|--------|------|---------------|
| Date range | from/to date pickers | client-side on `completed_at_utc` |
| Workout type | multi-select chips | client-side on `workout_type` |
| Has modifications | boolean toggle chip | client-side: `exercise_modifications.length > 0` |
| Status | `Completed` / `In Progress` chips | client-side on `completed_at_utc != null` |

All filters applied client-side on the already-loaded `recent_executions` array.

Empty state when filters produce 0 results: *"No workouts match your filters."* + "Clear filters" button.

---

## Implementation Notes

### Sequencing Constraints

1. **Schema migrations first:** `user_gamification_preferences`, `user_pr_records`, `user_pr_history`, `exercise_modifications` field, `note` fields on sections/exercises — these block everything else.
2. **Calculators before `RecordWorkoutCompletion`:** New domain modules must exist before the completion pipeline is updated.
3. **Messaging context check:** Verify `class_booking` context type before SlotPopup chat implementation.
4. **Meilisearch index:** Set up `user_pr_records` index before Pantheon search UI.

### Cross-Context Boundaries

- `advancement_count` in `user_stats` is updated by the Pantheon application layer (not gamification domain) when a PR record is created/improved — cross-context write via application service, not direct DB query.
- Perseverance calculator receives `exercise_modifications` from execution context via the `RecordWorkoutCompletion` command input — passed as data, no direct cross-context DB query.

### Existing Code Preserved

- `StreakCalculator` remains for backward compatibility with any existing tests; `DayStreakCalculator` is a new module.
- `PRDetector` (auto-execution PRs) and `total_prs` field remain unchanged — they power existing milestone badges.
- Existing `ChatSection` component reused as-is for both AssignedWorkoutPanel and SlotPopup.
