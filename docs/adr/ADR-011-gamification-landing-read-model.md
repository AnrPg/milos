# ADR-011: Gamification Landing Read Model
Date: 2026-06-09
Status: Accepted

## Context

Phase 7 introduces the first end-to-end gamification slice: streaks, PRs,
seasonal challenges, leaderboard opt-in, and the authenticated landing page
that surfaces those features immediately after workout completion.

The design doc imposes a few non-negotiable constraints that directly shape the
implementation:

- gamification reacts to workout completion through internal PubSub events
- leaderboard and analytics reads use PostgreSQL materialized views
- landing page reads use Redis cache-aside with 60 second TTL
- controllers must stay thin and route all cross-context orchestration through
  application services

The main decision is how to keep the landing page fast and immediately
consistent enough for user feedback without pulling scheduling, workouts,
execution, notifications, and gamification into a single tightly coupled read
path.

## Decision

The system will use a hybrid read/write design:

- `Execution` remains the producer of the semantic `"workout:completed"` event
- `Gamification.EventHandler` reacts to that event and updates durable
  gamification state inside the `Gamification` context
- gamification state is persisted in dedicated tables:
  `user_stats`, `user_achievements`, `seasonal_challenges`,
  `user_challenge_progress`, and `leaderboard_opt_ins`
- the landing page is served by a dedicated application service that composes
  execution history, gamification state, leaderboard, and optional membership
  data, then caches the assembled payload in Redis for 60 seconds
- leaderboard reads come from PostgreSQL materialized views refreshed by an
  Oban worker on a schedule and opportunistically after writes
- challenge completion emits a semantic `"gamification:challenge_completed"`
  PubSub event so Notifications can react independently

## Rationale

Updating `user_stats`, badges, PR counters, and challenge progress on workout
completion gives the user immediate feedback without forcing controllers or the
`CompleteWorkout` application service to know gamification internals.

Keeping the landing payload as a composed read model avoids denormalizing every
landing concern into a single table while still allowing Redis to absorb repeat
reads. This respects the bounded contexts: execution owns workout history,
gamification owns progression state, and the landing application service merely
assembles public read APIs.

Using materialized views for leaderboard data keeps ranking queries cheap and
stable as execution history grows. Refreshing them through Oban makes the cost
explicit and operationally observable.

## Alternatives Considered

Directly invoking gamification from `CompleteWorkout`:
rejected because it would bypass the required PubSub event topology and tighten
coupling between application services and a downstream bounded context.

Recomputing streaks and challenges from raw execution history on every landing
request:
rejected because it would increase latency and duplicate business logic across
queries instead of storing a durable progression state.

Persisting the full landing page as one denormalized document:
rejected because it would make ownership unclear, complicate invalidation, and
blend execution, gamification, and future coaching data into one mutable store.

## Consequences

Workout completion now has two layers of feedback:
the primary execution write succeeds first, then gamification and notifications
react asynchronously through PubSub. This preserves resilience for non-critical
side effects while keeping the system architecture aligned with the design doc.

Redis caching becomes part of the landing-page correctness model. Any command
that changes landing-facing state must invalidate the cache for the affected
user.

Leaderboard freshness is intentionally near-real-time rather than fully
transactional. Users may see a short delay before the ranking reflects newly
completed workouts until the view is refreshed.

## Implementation Notes

- Added dedicated gamification persistence for stats, achievements, seasonal
  challenges, per-user challenge progress, and leaderboard opt-ins, plus the
  `weekly_leaderboard` materialized view and a 15-minute Oban refresh job.
- Gamification updates are now triggered from the existing
  `"workout:completed"` PubSub event path. The handler recomputes streaks from
  execution history, stores PR events as hidden `user_achievements` records
  using a `pr_event:*` key namespace, awards visible milestone badges, advances
  active challenges, and invalidates the landing cache.
- The landing page is served through a dedicated application service backed by
  Redis cache-aside when Redix is available, with a graceful no-cache fallback
  in environments where Redis is not running.
- Execution read models were enriched with workout title/type summaries so the
  landing-page history modal can display useful context without introducing a
  separate execution-history table.
- Admin challenge management shipped as a focused `/admin/challenges` surface
  with overlap enforcement and progress summaries, but custom challenge logic is
  intentionally generic for now and is tracked as technical debt.
- The admin challenge surface now supports create, edit, list, and detail
  inspection. The admin detail read joins gamification-owned challenge progress
  with Identity public user records in an application service so the screen can
  show participant nicknames, roles, progress ratios, completion counts, and
  aggregate participation metrics without crossing bounded-context internals.
- Membership data is not yet persisted anywhere in the current project state,
  so the landing-page membership card is implemented as an optional panel that
  remains hidden until Phase 8 introduces the membership model.
- Follow-up hardening on 2026-06-10 corrected the leaderboard materialized-view
  aggregation to avoid cross-join overcounting, moved workout-completion
  orchestration out of the gamification command and into a dedicated
  application service, and added OpenAPI request casting to the landing
  controller so Phase 7 endpoints follow the same contract-first path as the
  rest of the API.
- Streak windows and monthly shield replenishment are now anchored to the
  athlete's signup date so weekly and monthly progression is evaluated
  relative to each user's lifecycle instead of fixed calendar Mondays.
- Landing-page density refinements on 2026-07-15 remain entirely within the
  existing read model: member and athlete challenge panels render only when
  `active_challenges` contains a current challenge, while leaderboard opt-in
  state controls whether the full ranking card or a compact hover/focus entry
  point is shown. No persistence, cache, or API contract changes were needed.
- Workout-history type filters are derived from the completed executions in
  the landing payload and appear only when at least two distinct workout types
  are available. Pantheon cards reuse the existing PR history query and PR
  update modal on both the landing page and the full Pantheon route.

## Read-Model Efficiency Amendment — 2026-07-15

The landing application service consumes context-owned batch query APIs and a
dedicated projection port; it does not import Ecto, Repo, or schemas. Direct
thread message summaries are fetched in one bounded query rather than one query
per thread. Quote selection uses a precomputed/random-key strategy rather than
`ORDER BY RANDOM()` so growth does not introduce a full-table sort.
