# Gym App — Product Requirements Document
**Date:** 2026-06-05  
**Status:** Approved  
**App Name:** Milos Training

---

## 1. Overview

A fully responsive web application for a gym owner who runs both in-person group classes and personalized online programming for remote athletes. Non-profit motivation (no ads, no dark patterns). Self-hosted on owner's servers, all free/OSS stack.

**Design principles:** Minimal, colorful, uncluttered, simplistic. Mobile-first.

---

## 2. Architecture Constraints ⚠️ NON-NEGOTIABLE

> **FOR CODE AGENTS:** Every rule in this section is a hard constraint.
> Violating any of them requires explicit human approval before proceeding.
> Do not interpret, relax, or work around these rules. If a task seems to
> require violating one, STOP and ask.

---

### 2.1 Hexagonal Architecture — Strict 4-Layer Rule

The backend is organized in exactly four layers. **No layer may depend on a layer above it. No layer may skip a layer below it.**

```
┌─────────────────────────────────────────────────────┐
│  INTERFACE LAYER                                    │
│  Phoenix Controllers, Channels, Plugs, Sockets      │
│  → Translates HTTP/WS into Application calls        │
│  → ZERO business logic allowed here                 │
├─────────────────────────────────────────────────────┤
│  APPLICATION LAYER                                  │
│  Use Cases / Application Services                   │
│  → Orchestrates Domain + Infrastructure calls       │
│  → No direct Ecto/DB/HTTP knowledge                 │
├─────────────────────────────────────────────────────┤
│  DOMAIN LAYER                                       │
│  Pure Elixir business logic — no external deps      │
│  WorkoutMaterializer, StreakCalculator, PRDetector, │
│  TimerSequenceBuilder, BookingPolicy               │
│  → No Ecto, no Repo, no HTTP, no Redis              │
├─────────────────────────────────────────────────────┤
│  INFRASTRUCTURE LAYER                               │
│  Implements ports defined by Domain/Application     │
│  Ecto Repos, MeilisearchClient, PushDispatcher,    │
│  RedisCache, ObanWorkers                            │
└─────────────────────────────────────────────────────┘
```

**Enforcement rules:**
- Controllers call Application Services — never Repo, never Domain modules directly.
- Domain modules are pure functions: same input → same output, no side effects.
- Infrastructure modules implement behaviours (Elixir `@behaviour`) defined in Application/Domain.
- Tests for Domain modules: no ExUnit mocks, no DB, no fixtures — pure unit tests only.

---

### 2.2 Phoenix Contexts as Bounded Contexts — Strict Boundary Rule

The backend is divided into the following contexts. **No context may call another context's internal modules (schemas, private queries, Repo calls). Cross-context communication is ONLY via the context's public API functions or via PubSub events.**

```
MilosTraining.Identity       → users, auth, registration, role management
MilosTraining.Scheduling     → scheduled_classes, bookings, approval flow
MilosTraining.Workouts       → master_workouts, sections, exercises, variations,
                        materialization logic, assigned_workouts
MilosTraining.Execution      → workout_executions, scores, exercise_notes
MilosTraining.Gamification   → user_stats, achievements, streaks, PRs,
                        seasonal_challenges, leaderboard
MilosTraining.Coaching       → admin_athlete_notes, analytics aggregates
MilosTraining.Notifications  → push_subscriptions, notification records,
                        push dispatch
MilosTraining.Finance        → packages, memberships, invoices, credits,
                        entitlements, referrals
MilosTraining.Analytics      → durable product events and operational projections
MilosTraining.Feedback       → reviews, questionnaires, moderation lifecycle
MilosTraining.Wellbeing      → injury reports, healing history, training limitations
MilosTraining.Messaging      → direct/contextual threads, participants, messages
MilosTraining.Pantheon       → personal records and score history
MilosTraining.Organizations  → tenants, memberships, domains, settings,
                        and one-time registration invitations
```

These post-MVP contexts are authoritative, not auxiliary folders. They follow the
same public-API-only cross-context rule as the original seven contexts. The
`MilosTraining.Application.*` namespace is an orchestration layer and is not itself
a bounded context.

**Enforcement rules:**
- `Scheduling` must NOT call `MilosTraining.Gamification.Repo` or any Gamification schema directly.
- `Execution` completing a workout → broadcasts a PubSub event → `Gamification` and `Notifications` subscribe and react independently.
- Shared data structures that cross contexts are plain maps or dedicated structs — never Ecto schemas from another context.
- If a feature requires data from two contexts, an **Application Service** (§2.4) orchestrates the calls.

---

### 2.3 Light CQRS — Commands and Queries are Separate Modules

Within each context, reads and writes live in separate sub-modules:

```
MilosTraining.Workouts.Commands   → CreateWorkout, UpdateWorkout, AssignWorkout,
                             DeleteWorkout
MilosTraining.Workouts.Queries    → GetWorkoutForDate, MaterializeWorkout,
                             GetWeekView, GetScaleInstances

MilosTraining.Scheduling.Commands → CreateSlot, UpdateSlot, DeleteSlot,
                             SubmitBooking, ApproveBooking, RejectBooking
MilosTraining.Scheduling.Queries  → GetCalendarWeek, GetSlotPreview,
                             GetPendingBookings

MilosTraining.Gamification.Commands → RecordWorkoutCompletion, AwardBadge,
                               UpdateStreak, RecordPR
MilosTraining.Gamification.Queries  → GetUserStats, GetLeaderboard,
                               GetActiveChallenges, GetBadges
```

**Enforcement rules:**
- A Command module performs writes via Ecto changesets only — no raw SQL mutations.
- A Query module performs reads — it may use Repo directly but must never mutate state.
- Controllers and Application Services call Commands or Queries, never both mixed in one function chain without going through a service boundary.

---

### 2.4 Application Services for Cross-Context Operations

Any operation touching more than one bounded context MUST be implemented as an Application Service in `MilosTraining.Application.*`. Controllers call Application Services — never orchestrate cross-context logic themselves.

**Canonical Application Services:**

```elixir
MilosTraining.Application.CompleteWorkout
  # Execution.record → Gamification.update_stats →
  # Gamification.detect_prs → Notifications.dispatch_if_notes

MilosTraining.Application.ApproveBooking
  # Scheduling.approve → Notifications.notify_member →
  # Oban.cancel_timeout_job

MilosTraining.Application.SubmitBooking
  # Scheduling.create_booking → Notifications.notify_admin →
  # Oban.schedule_timeout_job

MilosTraining.Application.RegisterUser
  # Identity.create_user → Notifications.create_push_subscription_stub

MilosTraining.Application.WriteAthleteNote
  # Coaching.create_note → Notifications.notify_athlete
```

**Enforcement rules:**
- Each Application Service is a single public `call/N` function.
- It uses `with` for error propagation — no nested case/if chains.
- It does NOT contain business logic — that lives in Domain modules.
- It does NOT contain DB queries — those live in Query modules.
- Failure in a non-critical step (e.g., push notification) must NOT roll back the primary transaction.
- Application and Domain compile dependencies are checked by `mix milos.architecture`;
  the same gate rejects controller imports of context internals and infrastructure.
- Durable cross-context effects use a transactional Oban handoff owned by the
  context write adapter. Application services pass plain delivery data, never an
  infrastructure job module or changeset.

---

### 2.5 Contract-First API — Spec Before Code

**Every public endpoint must have an OpenAPI spec entry BEFORE the Phoenix controller is written.** The spec is the single source of truth.

```
Workflow:
  1. Write/update OpenAPI spec  (open_api_spex)
  2. Run openapi-typescript     → generates Next.js typed client
  3. Write Phoenix controller   → must conform to spec
  4. Write tests                → validate against spec
```

**Enforcement rules:**
- Never write a controller action without a matching spec entry.
- If spec and implementation diverge: fix the implementation OR file a spec change — never silently diverge.
- Phoenix Channels (async events) must have corresponding documentation in the spec or a separate AsyncAPI doc.
- The generated TypeScript client (`/apps/web/src/api/generated/`) is read-only — never manually edited.

---

### 2.6 Repository Pattern — No Direct Repo Calls Outside Contexts

**`Repo` is only callable from Infrastructure modules inside the owning context.** Controllers, Application Services, and Domain modules must never call `Repo` directly.

```elixir
# ❌ FORBIDDEN — controller accessing Repo
def show(conn, %{"id" => id}) do
  workout = Repo.get!(MasterWorkout, id)   # VIOLATION
end

# ❌ FORBIDDEN — Application Service bypassing context
def call(user_id) do
  Repo.all(from u in User, where: u.id == ^user_id)  # VIOLATION
end

# ✅ CORRECT — controller calls context public API
def show(conn, %{"id" => id}) do
  workout = Workouts.Queries.get_workout!(id)
end
```

---

### 2.7 Infrastructure Patterns — Required Implementations

These patterns are required and must be implemented exactly as specified:

#### Phoenix PubSub Internal Event Bus
Cross-context side effects (gamification updates, push notifications) are triggered via `Phoenix.PubSub.broadcast/3`. Each subscribing context registers its own handler independently. Direct function calls across contexts for side effects are forbidden.

```elixir
# After workout completion, Execution broadcasts:
Phoenix.PubSub.broadcast(MilosTraining.PubSub, "workout:completed",
  {:workout_completed, %{user_id: ..., execution_id: ..., scale_level: ...}})

# Gamification.EventHandler subscribes and reacts independently
# Notifications.EventHandler subscribes and reacts independently
```

#### Phoenix Channels External Real-Time Delivery
User-visible real-time updates fan out from internal PubSub events through Phoenix Channels. The REST API remains the source of truth for full payload reads, while channels carry low-latency update or invalidation events.

Required topics:

- `schedule:lobby` → authenticated schedule viewers receive `schedule:refresh` events after slot CRUD, booking submission/resolution, and timeout escalation.
- `notifications:{user_id}` → the owning user receives `notifications:changed` events after notification creation or bulk read.
- `execution:{execution_id}` → the owning athlete or an admin receives `execution:progress_updated`, `execution:note_submitted`, and `execution:completed` events during workout execution.

Channel payloads must be plain maps and must never embed foreign Ecto schemas.

#### Redis Cache-Aside for Landing Page
`user_stats`, `recent_executions`, and `active_challenges` are cached in Redis with TTL 60 seconds. Cache is invalidated on `workout_execution` insert or gamification update. The Landing Page API endpoint reads from cache first; DB only on miss.

#### Oban Job Chaining for Booking Timeouts
Every pending booking schedules a `MilosTraining.Workers.BookingTimeoutJob` via Oban at `inserted_at + booking_timeout_minutes`. The job checks current status: if still `:pending` → push alert to Admin. If already resolved → no-op. Jobs are cancelled via `Oban.cancel_job/1` on approval/rejection.

#### PostgreSQL Materialized Views for Leaderboard & Analytics
`weekly_leaderboard` and `coaching_aggregates` are PostgreSQL materialized views refreshed every 15 minutes via a dedicated `MilosTraining.Workers.RefreshLeaderboardJob`. Refresh uses `CONCURRENTLY` to avoid table locks. Query modules read from views directly.

#### Optimistic UI for Execution Mode
Workout step check-offs in the Execution Mode update Zustand local state immediately (no await). The API call persists asynchronously. On error: Zustand rolls back the check, a toast error is shown. This pattern applies ONLY to Execution Mode check-offs — all other mutations are synchronous.

---

### 2.8 Forbidden Patterns

The following are explicitly forbidden. Any code introducing these requires human approval before merge:

| Forbidden | Reason |
|---|---|
| Business logic in Phoenix controllers | Violates hexagonal layer rule |
| Direct `Repo` calls outside owning context | Violates bounded context rule |
| Cross-context Ecto schema imports | Violates bounded context rule |
| Raw SQL mutations (use Ecto changesets) | Bypasses validation and audit trail |
| Controller orchestrating multiple contexts | Application Service responsibility |
| Frontend manually editing generated API client | Contract drift |
| Domain module importing Phoenix/Ecto | Violates hexagonal purity |
| Polling for real-time features (use Channels) | Violates real-time architecture decision |
| Full Event Sourcing | Overkill for this scale |
| Microservices split | Overkill for this scale |
| GraphQL | REST + OpenAPI is the contract layer |

---

## 3. User Roles

> **Multi-tenant amendment — 2026-07-18:** ADR-055 supersedes the original
> global-role model below. Authentication principals are global, while roles
> and authorization are scoped through organization memberships. The original
> matrix remains the functional role definition within one organization.

| Role | Description |
|---|---|
| **Admin** | Gym owner/trainer. Full access. Sees inline edit buttons on all standard pages. |
| **Gym Member** | Attends group classes. Books slots, executes typed workouts. |
| **Athlete** | Personal training client. Receives bespoke assigned workouts only. |

- Role stored as enum: `:admin | :member | :athlete`
- User chooses `:member` or `:athlete` at registration. Admin can change any user's role at any time.
- Admin is not a separate account type — it is a role flag on the user record.

### Permission Matrix

| Page / Feature | Admin | Member | Athlete |
|---|:---:|:---:|:---:|
| Landing Page (`/`) | ✅ | ✅ | ✅ |
| Know More (`/about`) | ✅ | ✅ | ✅ |
| Class Schedule (`/schedule`) | ✅ | ✅ | ❌ |
| Workouts Page (`/workouts`) | ✅ | ✅ | ❌ |
| Assigned Workouts (`/my-workouts`) | ✅ | ❌ | ✅ |
| Workout Execution Mode | ✅ | ✅ | ✅ |
| Admin Dashboard (`/admin`) | ✅ | ❌ | ❌ |
| Approve/reject bookings | ✅ | ❌ | ❌ |
| Add/edit/delete time slots | ✅ | ❌ | ❌ |
| Create/edit workouts | ✅ | ❌ | ❌ |
| View all user notes/modifications | ✅ | ❌ | ❌ |

---

## 4. Core User Flows

### Flow 1 — Class Booking (Member)
```
Member opens /schedule
  → Selects training type via filter chips (calendar filters to that type only)
  → Clicks available time slot
  → Corner popup shows workout preview (collapsible sections)
  → Clicks "Book"
  → [auto_approve: true]  → Confirmed immediately + push to Member
  → [auto_approve: false] → Status: Pending + push to Admin
       → Admin approves (optional message) → push to Member
       → Admin rejects  (optional message) → push to Member
       → [No response after X minutes]     → alert push to Admin
```

### Flow 2 — Workout Discovery & Execution (Member)
```
Member opens /workouts
  → Clicks training type (big button)
  → Swipeable week-view appears
  → Each day shows available scale boxes (color-coded: beginner/intermediate/advanced)
  → Member clicks desired scale box
  → Week-view minimizes → selected scaled workout displayed in full
  → Clicks "Start Workout" → Workout Execution Mode (fullscreen)
       → Timer starts (pre-configured per section)
       → Step-by-step checklist (sets × reps expanded to individual rounds)
       → Select text within an exercise label
       → Right-click (desktop) or long-press selected text / word (mobile)
       → Annotation modal opens with multi-select quick tags + free-text note
       → Selected text is highlighted in-place; hover/click reveals attached annotations
       → Admin notification includes the associated selected text
  → Completion → score input per scoreable section → gamification update
```

### Workout Scaling — Materialization Logic
```
Admin creates master WOD with exercises.
For each exercise, Admin optionally adds scale-specific variations.

At query time, the system materializes scale instances:
  - One instance per scale level that appears in ≥1 variation across the workout
  - Each instance inherits base workout, overrides only exercises with a variation
    for that scale
  - Scale with zero variations → workout = base (original); no separate instance spawned

Example WOD A:
  Exercise 1: variations for [beginner, intermediate]
  Exercise 2: variations for [beginner, advanced]
  → Materialized: WOD-A/beginner, WOD-A/intermediate, WOD-A/advanced

Example WOD B:
  Exercise 1: variations for [intermediate, advanced]
  → Materialized: WOD-B/intermediate, WOD-B/advanced
  → WOD-B/beginner = base (no separate instance)
```

### Flow 3 — Assigned Workout Execution (Athlete)
```
Athlete opens /my-workouts
  → Week-view shows bespoke workouts assigned to them
  → Clicks workout → expand preview → "Execute"
  → Workout Execution Mode (same as Flow 2)
```

### Flow 4 — Admin Workout Creation
```
Admin → /admin/workouts → "New Workout"
  → Linear form:
     1. Title, type, sections
     2. Per section: exercises (base), inline scale variations, timer config
     3. Spawned instances preview (tabbed: Base | Beginner | Intermediate | Advanced)
  → Save → instances materialized at query time
  → Assign to date/time slot (Members) or directly to athlete(s) (Athletes)
```

### Flow 5 — Membership Management (Admin)
```
Admin → /admin → Tab 1
  → Fuzzy search bar (Meilisearch live suggestions) for member lookup
  → Or click member in list
  → Drill down:
       → Manual entry: amount_paid, payment_date, expiration_date, notes
       → Payment history (all past records)
       → Renew / Cancel membership
```

### Flow 6 — Financial Analytics (Admin)
```
Admin → /admin → Tab 1
  → Monthly revenue chart
  → Active memberships count
  → Expiring in 30 days (alert list)
  → Drill down to member (fuzzy search or list click)
       → Payment history, amounts, dates
       → Inline edit membership fields
       → Renew / Cancel
```

### Flow 7 — Coaching Analytics (Admin)
```
Admin → /admin → Tab 2
  → Aggregate: workout frequency trends, top types, inactive athletes
  → Drill down to athlete (fuzzy search or list click)
       → Workout history timeline
       → Scores per workout type (progress charts)
       → Notes/modifications submitted by athlete (highlighted)
       → Admin writes note to athlete → appears on athlete's Landing Page
```

### Flow 8 — Registration
```
New user receives one-time invitation → /register?invite=<opaque token>
  → Server infers organization and intended role from the invitation
  → Enters: nickname (unique) + password
  → Registration atomically consumes the invitation and creates membership
  → First login → Landing Page
```

---

## 5. Data Models

### Authentication & Users
```
users
  id (uuid), nickname (string, unique), password_hash (string)
  role: :admin | :member | :athlete  [transitional; superseded by membership role]
  leaderboard_opt_in (boolean, default: false)
  inserted_at, updated_at

organizations
  id (uuid), slug (string, unique), name (string)
  status: :active | :suspended | :archived
  inserted_at, updated_at

organization_memberships
  id (uuid), organization_id → organizations, user_id → users
  role: :owner | :admin | :coach | :member | :athlete
  status: :invited | :active | :suspended | :revoked
  joined_at, inserted_at, updated_at

registration_invitations
  id (uuid), organization_id → organizations
  token_digest (binary, unique), role, expires_at
  issued_by_user_id → users, redeemed_by_user_id → users
  redeemed_at, revoked_at, inserted_at, updated_at

organization_domains
  id (uuid), organization_id → organizations
  host (string, unique), verified_at, primary

organization_settings
  id (uuid), organization_id → organizations (unique)
  timezone, default_locale, invitation_lifetime_seconds, settings (jsonb)

memberships
  id, user_id → users
  amount_paid (decimal), payment_date (date)
  expiration_date (date), notes (text)
  inserted_at
  [Multiple records per user = full payment history]

push_subscriptions
  id, user_id → users
  endpoint (string), keys (jsonb: {p256dh, auth})
  inserted_at

notifications
  id, user_id → users
  type: :booking_approved | :booking_rejected | :booking_pending
        | :booking_timeout | :workout_note | :admin_note
  payload (jsonb), read_at (utc_datetime), inserted_at
```

### Workout System
```
master_workouts
  id (uuid), title (string)
  type: :crossfit | :strength | :gymnastics | :aerobics | :flexibility | :recovery
  created_by → users (admin)
  inserted_at, updated_at

workout_sections
  id (uuid), master_workout_id → master_workouts
  parent_section_id → workout_sections (nullable — for sub-sections e.g. "Main Course > Part A")
  name (string), order (integer)
  scoreable (boolean, default: false)
  score_config (jsonb: {
    type: :time | :reps | :weight | :rounds | :load,
    unit: "min" | "reps" | "kg" | "lb" | "rounds+reps",
    label: string
  })
  timer_config (jsonb: {
    type: :emom | :amrap | :for_time | :tabata | :fixed_duration | :rest | :untimed,
    interval_seconds: integer,   // EMOM: interval length
    duration_seconds: integer,   // total section duration
    rounds: integer,
    work_seconds: integer,       // Tabata work phase
    rest_seconds: integer        // Tabata/rest phase
  })
  [If a sub-section has no timer_config, it inherits the parent section's timer.
   A sub-section with timer_config: {type: :untimed} explicitly pauses the timer.]
  inserted_at

workout_exercises
  id (uuid), workout_section_id → workout_sections
  name (string), description (text)
  base_sets (integer), base_reps (integer), base_duration_seconds (integer)
  order (integer)

exercise_variations
  id (uuid), workout_exercise_id → workout_exercises
  scale_level: :beginner | :intermediate | :advanced
  description (text), sets (integer), reps (integer), duration_seconds (integer)
  [Absence of a variation means: use base for that scale]
```

### Scheduling & Bookings
```
scheduled_classes
  id (uuid), master_workout_id → master_workouts
  training_type: :crossfit | :strength | :gymnastics | :aerobics | :flexibility | :recovery
  [Denormalized from master_workout.type for efficient calendar filtering without JOIN]
  scheduled_at (utc_datetime), capacity (integer)
  auto_approve (boolean, default: false)
  booking_timeout_minutes (integer, default: 60)

bookings
  id (uuid), scheduled_class_id → scheduled_classes, user_id → users
  status: :pending | :approved | :rejected | :cancelled
  admin_message (text, optional)
  inserted_at, updated_at

assigned_workouts
  id (uuid), master_workout_id → master_workouts
  scheduled_for (date), admin_notes (text)
  inserted_at

assigned_workout_athletes   [join table — one assignment can target many athletes]
  id, assigned_workout_id → assigned_workouts, athlete_id → users
```

### Execution & Progress
```
workout_executions
  id (uuid), user_id → users, master_workout_id → master_workouts
  scale_level: :beginner | :intermediate | :advanced | nil (base)
  source: :class_booking | :assigned | :self_selected
  started_at_utc (utc_datetime_usec), started_at_tz (string, e.g. "Europe/Athens")
  completed_at_utc (utc_datetime_usec), completed_at_tz (string)
  section_scores (jsonb: [
    { section_id, section_name, score_type, value, unit }
  ])
  exercise_notes (jsonb: [
    {
      id,
      exercise_id,
      selected_text,
      selection_start,
      selection_end,
      tags: [string],
      note_text,
      inserted_at,
      updated_at
    }
  ])
  inserted_at

admin_athlete_notes
  id, admin_id → users, athlete_id → users
  body (text), inserted_at
```

### Gamification
```
user_stats   [denormalized — fast Landing Page reads]
  id, user_id → users (unique)
  current_streak (integer), longest_streak (integer)
  total_workouts (integer), total_prs (integer)
  current_streak_shields (integer, default: 1)
  last_workout_at (utc_datetime)
  consistency_score (float)  // % active weeks in last 12
  updated_at

user_achievements
  id, user_id → users
  badge_key (string, e.g. "streak_7", "workouts_50", "type_crossfit_mastery")
  earned_at (utc_datetime)

seasonal_challenges
  id, title (string), description (text)
  criteria_type: :workout_count | :workout_type_count | :pr_count | :custom
  criteria_value (jsonb: { count, type_filter, ... })
  badge_key (string), badge_label (string)
  starts_at (date), ends_at (date)
  created_by → users (admin)
  [Max 3 active challenges simultaneously]

user_challenge_progress
  id, user_id → users, challenge_id → seasonal_challenges
  progress (integer), completed_at (utc_datetime, nullable)

leaderboard_opt_ins
  id, user_id → users (unique), opted_in_at (utc_datetime)
```

---

## 6. Gamification System — "Streak × Performance"

### Four Pillars

**1. Streak Engine**
- Weekly streak: ≥ N workouts/week (N configurable by Admin, default: 2) = +1 streak
- Streak shield: 1 per month, prevents reset for 1 missed week
- Consistency score: % active weeks in last 12 weeks
- Milestone badges (attendance): 1st, 10, 25, 50, 100, 200, 365 workouts

**2. PR Board**
- Personal Record: improvement of score on any scoreable section → PR flag
- PR milestone badges: First PR, 5, 10, 25, 50 PRs
- Type mastery badges (≥10 workouts per type):
  CrossFit Devotee · Iron Lifter · Gymnastics Adept · Cardio Machine · Flex Master · Recovery Pro
- Improvement % display: "Improved time by 12% this month"

**3. Seasonal Challenges (Admin-defined)**
- Admin creates: title, description, date range, criteria, custom badge
- Users see active challenge + progress bar on Landing Page
- Max 3 concurrent active challenges

**4. Opt-in Leaderboard**
- Default: off. User opts in explicitly.
- Weekly leaderboard: ranking by workouts completed this week
- Monthly leaderboard: ranking by PRs this month
- Shows nickname only. Visible only to opted-in users.

---

## 7. Workout Execution Mode

**Layout: Timer-Dominant Stacked (Option A)**

```
┌─────────────────────────────┐
│  EMOM · Round 2/5      ⏸ ✕ │
│  ┌─────────────────────────┐│
│  │                         ││
│  │         0:42            ││
│  │      every 1:00         ││
│  └─────────────────────────┘│
│  Main Course — Part A        │
│  10 Push-ups · 8 Pull-ups    │
│  [✓ Set 1] [▶ Set 2] [ Set 3]│
│  ─────────────────────────── │
│  [ ⏸ Pause ]  [ → Skip ]     │
│  [ 📝 Note  ]                │
└─────────────────────────────┘
```

**Timer Sequence Engine:**
- At workout load: builds ordered `TimerSequence` from sections (depth-first, by `order`)
- Each `TimerSegment`: `{ section_id, timer_config, steps[] }`
- Timer display per type:

| Type | Display |
|---|---|
| emom | "EMOM — :45 / every 1:00" + round X/N |
| amrap | "AMRAP — 12:43 remaining" |
| for_time | "For Time — 05:21" (count up) |
| tabata | "Work: :15 / Rest: :10 — Round 3/8" |
| fixed_duration | "4:00 — Round 1/2" (countdown) |
| rest | ":30 Rest" (countdown) |
| untimed | "No Timer" |

**Auto-advance vs Manual check-off:**

| Timer Type | Advancement |
|---|---|
| fixed_duration | **Auto** — on timer expiry |
| emom | **Auto** — each interval expires |
| tabata | **Auto** — on final cycle |
| rest | **Auto** — on timer expiry |
| amrap | **Auto** — on timer expiry → score prompt |
| for_time | **Manual** — athlete checks off when done |
| untimed | **Manual** — athlete checks off manually |

**Pause / Resume:**
- Pause: timer freezes, auto-advance disabled, UI shows "Paused"
- Resume: 3-second countdown (configurable off) → timer continues
- Athlete can manually check off a step before timer expires (timer cancelled, immediate advance)
- Scoreable section transition: score input modal appears before next segment starts
- Offline resilience: current workout cached in Service Worker

---

## 8. Page-by-Page Spec

### `/` — Landing Page
- **Gamification panel:** streak counter + consistency score + active challenge progress bars + badge grid + opt-in leaderboard snippet (weekly/monthly toggle)
- **Membership panel:** subtle card — expiration date, last paid, amount, admin notes (shown only if they exist)
- **Workout history:** scrollable list → click opens modal with full workout, modifications highlighted in color, scores per section
- **Admin view:** same as above for self + shortcut links to Dashboard

### `/schedule` — Class Schedule
- Filter chips (training types) → calendar filters to selected type only
- Calendar views: week / 3-day / month (toggle, responsive default: 3-day on mobile)
- Available slots: clickable. Full/unavailable: greyed out.
- Hover/click → corner popup: workout preview (collapsible sections), spots remaining, booking button
- Booking flow: Book → Pending/Confirmed → push notification to user
- **Admin only:** "+" button per empty cell (add slot), click existing slot → edit popup (capacity, auto_approve, timeout, workout, type), delete slot (confirmation if bookings exist), approve/reject bookings inline

### `/workouts` — Workout Browsing (Members)
- Step 1: Big training type buttons
- Step 2: Swipeable week-view; each day shows available scale boxes (color-coded, duration, highlight)
- Step 3: Click scale box → week-view minimizes → full workout displayed → "Start Workout"
- Admin: inline "Edit" button on workout display

### `/my-workouts` — Assigned Workouts (Athletes)
- Week-view with bespoke workouts assigned to athlete
- Click → expand preview → "Execute" → Execution Mode
- Admin: sees all athletes' assigned workouts, inline edit, assign new workout

### Workout Execution Mode *(overlay — activated from /workouts, /my-workouts, or /schedule)*
- Fullscreen takeover (see Section 6 above)

### `/about` — Know More
- Static marketing page: brand, services, contact
- Public (no auth required)

### `/admin` — Admin Dashboard
- **Tab 1 — Financial:** revenue chart, active memberships, expiring soon list, fuzzy member search → drill-down (edit membership, payment history, renew/cancel)
- **Tab 2 — Coaching:** aggregate trends (frequency, top types, inactive alerts), fuzzy athlete search → drill-down (history, scores, notes, write note to athlete)

### `/admin/workouts` — Content Management
- List of master workouts (filter by type)
- "New Workout": linear form — title/type → sections → exercises + inline scale variations + timer config per section → spawned instances preview (tabbed) → save
- Edit/delete existing workouts

### `/admin/schedule` — Schedule Management
- Create/edit/delete time slots (same UI as admin view on `/schedule` but dedicated page)

### `/admin/challenges` — Seasonal Challenges
- Create challenge: title, description, date range, criteria type + value, custom badge label
- Max 3 active simultaneously (enforced)
- View progress across all users

### `/admin/settings` — Global Settings
- `auto_approve` (boolean, default: false)
- `booking_timeout_minutes` (default: 60)
- `weekly_workout_target` for streak (default: 2)
- `streak_shield_reset_day` (monthly reset)
- `leaderboard_enabled` global kill-switch (boolean, default: true) — if false, opt-in has no effect for any user; Admin always sees the leaderboard regardless of this setting
- `resume_countdown_seconds` (integer, default: 3; set to 0 to skip countdown on timer resume)

---

## 9. Notifications

**Channels:** In-app (notification bell) + Web Push (Service Worker)

| Event | Recipient |
|---|---|
| Booking submitted (pending) | Admin |
| Booking approved/rejected | Member |
| Booking unanswered after X min | Admin (alert) |
| Workout note/modification submitted | Admin (includes associated selected text) |
| Admin note written to athlete | Athlete |
| Challenge completed | User |

---

## 10. Tech Stack

### Backend
| Concern | Technology |
|---|---|
| Framework | Elixir / Phoenix 1.7+ |
| Auth | Guardian (JWT) + Argon2 |
| Real-time | Phoenix Channels |
| Background Jobs | Oban |
| ORM | Ecto |
| Search | Meilisearch (self-hosted) |
| Push Notifications | Web Push Elixir + Oban workers |
| API Spec | OpenAPI (open_api_spex) |
| Cache | Redis 7+ (Redix) |
| Future Payments | Stripe SDK (architecture-ready, not implemented in v1) |

### Frontend
| Concern | Technology |
|---|---|
| Framework | Next.js 15 (App Router) + TypeScript |
| Styling | Tailwind CSS + shadcn/ui |
| Client State | Zustand |
| Server State | TanStack Query |
| Real-time | Phoenix Channels JS client |
| Calendar | react-big-calendar (customized) |
| Charts | Recharts |
| Timer | Custom hook: `useWorkoutTimer` |
| Forms | React Hook Form + Zod |
| Push | Service Worker + Web Push API |
| API Client | Auto-generated from OpenAPI spec (openapi-typescript) |
| Animations | Framer Motion (minimal) |

### Database & Infrastructure
| Concern | Technology |
|---|---|
| Database | PostgreSQL 16 |
| Search | Meilisearch (self-hosted) |
| Cache / PubSub | Redis 7+ |
| Asset Storage | MinIO (self-hosted, S3-compatible) |
| Reverse Proxy / SSL | Caddy (auto Let's Encrypt) |
| Deployment | Docker Compose |
| CI/CD | GitHub Actions + self-hosted runner |

### Deployment Architecture
```
Caddy (reverse proxy + TLS)
  ├── example.com      → Next.js container (:3000)
  └── example.com/api  → Phoenix container  (:4000)

Docker Compose services:
  next.js | phoenix | postgres | redis | meilisearch | minio
```

---

## 11. Non-Functional Requirements

- **API response:** < 200ms p95 (non-search)
- **Search suggestions:** < 50ms (Meilisearch)
- **Real-time latency:** < 100ms (Phoenix Channels)
- **Timer accuracy:** ± 100ms (requestAnimationFrame)
- **Security:** JWT (short-lived + refresh rotation), Argon2, RBAC on all controllers + Channels, Redis rate limiting on auth endpoints, HTTPS everywhere
- **Responsiveness:** Mobile-first. Breakpoints: < 768px (mobile), 768–1024px (tablet), > 1024px (desktop). Calendar: week-view desktop, 3-day default mobile.
- **Accessibility:** WCAG 2.1 AA minimum, keyboard navigation on all forms, sufficient color contrast for difficulty color-coding
- **Offline / PWA:** Service Worker for push notifications + workout data cache for Execution Mode resilience
- **Payments:** Architecture Stripe-ready; v1 is manual admin entry only

---

## 12. Open Items

- App name / branding: Milos Training
- Canonical scale level labels: "Beginner / Intermediate / Advanced" vs "Scaled / Rx / Rx+" — to be confirmed before DB migration
- Color palette for difficulty coding: TBD (design phase)
- Admin always sees the leaderboard regardless of `leaderboard_enabled` or user opt-in. ✅ Resolved in §8 `/admin/settings`.
