# ADR-009: Workout Execution Mode (Phase 4)

**Status:** Accepted  
**Date:** 2026-06-09  
**Authors:** anr

---

## Context

Phase 4 introduces the ability for athletes to execute workouts in real time. The feature requires:

1. A backend bounded context for recording execution lifecycle (start → complete).
2. A timer engine that converts the 18 workout section formats into a flat, executable sequence of timed segments.
3. A fullscreen frontend execution UI with per-exercise checklists, score capture, and text-linked exercise annotations.
4. A `/workouts` browsing flow that surfaces scheduled classes (no new schema) and allows scale level selection before launch.

The key design questions resolved before implementation:

- **All 18 timer formats fully implemented** (no archetype fallback).
- **`/workouts` browsing uses `scheduled_classes` as data source** (existing table, avoids new migration).
- **Athletes can pick scale level** if the workout has scale variations.

---

## Decision

### Bounded Context: `Execution`

A new bounded context `MilosTraining.Execution` was introduced, following the same hexagonal structure as `Workouts` and `Scheduling`:

```
execution/
  workout_execution.ex          # Ecto schema
  execution_store.ex            # dispatcher (adapter pattern)
  execution.ex                  # public context API
  ports/execution_store.ex      # behaviour
  commands/start_execution.ex   # validate workout + insert record
  commands/complete_execution.ex # user-ownership guard + update
  queries/get_execution.ex
  domain/timer_sequence_builder.ex  # pure, no Repo
infrastructure/execution/
  ecto_execution_store.ex
```

### `workout_executions` table

The schema stores: `user_id`, optional `master_workout_id` (nullable — workout may be deleted post-execution), `scale_level_slug`, `source` enum (`class_booking | assigned | self_selected`), timestamps with timezone (both `_utc` DateTime and `_tz` IANA string), and `section_scores` / `exercise_notes` as `{:array, :map}`. Each execution note is an annotation record keyed by its own `id`, the owning `exercise_id`, the `selected_text` anchor, optional `selection_start` / `selection_end` offsets, `tags`, free-text body, and timestamps.

### TimerSequenceBuilder (Pure Domain)

`MilosTraining.Execution.Domain.TimerSequenceBuilder.build/1` converts a materialized workout to a flat `[%{segment}]` list. Design rationale:

- **Depth-first traversal** mirrors the display order in the authoring canvas.
- **EMOM / complex_emom**: one segment per minute. Exercises with `interval_assignment` are filtered per round; plain EMOM repeats all exercises every round.
- **Even/Odd**: two-group alternation using `interval_assignment` parity.
- **Billat / Tabata / custom_hiit**: interleaved work/rest segments.
- **Cluster**: intra-set rest segments between sets.
- **HRR**: effort countdown + manual "recover to HR" segment.
- **Ladders / Pyramid**: `manual` kind (rep count is implicit in the format logic).
- **for_time / kcal_target**: `countup` kind (optional cap becomes isExpired trigger).
- **death_by**: `manual` (athlete self-increments reps per round).
- **rest sections**: `countdown`, exercises list empty.
- **untimed with children**: delegates to child section traversal.

### Application Services: `CompleteWorkout`, `SubmitExecutionNote`, `UpdateExecutionProgress`

`CompleteWorkout` wraps `Execution.complete_execution/3` and broadcasts `{:workout_completed, execution}` on `"workout:completed"`. `Notifications.EventHandler` and `Gamification.EventHandler` now subscribe independently, matching the Phase 4 event topology.

`SubmitExecutionNote` persists annotation-style execution notes and broadcasts `{:workout_note_submitted, %{execution_id, note}}` on `"workout:note_submitted"`. The Notifications context persists an admin-facing `workout_note` notification and enqueues an Oban-backed push-stub worker for the admin recipients.

`UpdateExecutionProgress` wraps `Execution.update_execution_progress/3` and broadcasts `"execution:progress_updated"` so other browser tabs observing the same execution stay in sync through channels.

### Real-Time Transport

Internal PubSub events are bridged to authenticated Phoenix Channels:

- `schedule:lobby` emits `schedule:refresh` when bookings or slots change.
- `notifications:{user_id}` emits `notifications:changed` after notification writes or mark-all-read.
- `execution:{execution_id}` emits `execution:progress_updated`, `execution:note_submitted`, and `execution:completed`.

The REST endpoints remain the authoritative read-model surface; channel payloads are lightweight synchronization events.

### Frontend Architecture

| Layer | File | Responsibility |
|---|---|---|
| API | `api/executions.ts` | startExecution, completeExecution, fetchTimerSequence |
| State | `stores/execution.ts` | Zustand: segments, currentSegmentIndex, status, scores/notes |
| Hook | `hooks/useWorkoutTimer.ts` | rAF-based wall-clock diff timer, ±100ms accuracy |
| Display | `components/workouts/execution/TimerDisplay.tsx` | Renders countdown/countup/manual, round pips |
| UI | `components/workouts/execution/WorkoutChecklist.tsx` | Text selection / long-press annotations + optimistic check-offs |
| Modals | `ScoreModal.tsx`, `NoteModal.tsx` | Score input + multi-select annotation tags |
| Shell | `components/workouts/execution/ExecutionMode.tsx` | Fullscreen, pause/resume with 3s countdown |
| Flow | `app/workouts/page.tsx` | 3-step: type → week view → scale |
| Execute | `app/workouts/[id]/execute/page.tsx` | Guard redirect, renders ExecutionMode |

### Timer accuracy

`useWorkoutTimer` uses `requestAnimationFrame` ticking against a wall-clock diff (`Date.now() - startTimeRef`). This avoids `setInterval` drift in throttled browser tabs. Accuracy spec is ±100ms (from `§11` of the design spec).

### Pause/Resume UX

Pause freezes the elapsed counter by recording `pausedElapsed`. Resume triggers a 3-second countdown (`resumeCountdown`), then calls `resumeTimer()` which restores the RAF loop. The countdown is driven by `setTimeout` (not RAF) since it only needs 1Hz resolution.

---

## Alternatives Considered

### Timer archetype collapse (5 archetypes)

Collapsing 18 formats into 5 execution archetypes would have simplified the `TimerSequenceBuilder` significantly but would have lost format-specific UX (e.g. EMOM per-minute exercise cycling, Billat work/rest labeling, Cluster intra-rest segments). Rejected in favor of full fidelity per user decision.

### Workout execution in /my-workouts instead of /workouts

Would have required extending the athlete calendar rather than creating a new flow. Rejected to avoid coupling execution entry-point to the assignment/coaching context.

### WebSocket for timer sync

Phoenix Channels could broadcast timer state for group classes. Deferred — the spec calls for client-side timer with server as record-of-truth only.

---

## Consequences

### Positive

- Full 18-format execution fidelity — no UX compromises.
- `TimerSequenceBuilder` is pure domain → trivially testable without DB or HTTP.
- `workout_executions` acts as the audit trail for athlete history (future: leaderboards, progress graphs).

### Negative / Deferred

- No real-time group timer sync (deferred to future phase).
- `section_scores` and `exercise_notes` stored as `{:array, :map}` — schema evolution still requires careful data migration if the annotation shape changes.
- No execution history UI yet — `listMyExecutions` API is wired but no frontend page to display history.
- No `/workouts` page link in nav yet — athlete will access it via direct URL or future nav update.

---

## Emergent Decisions

- Added `materialize_workout_for_scale/2` convenience function to `MilosTraining.Workouts` context to support the timer-sequence endpoint with a scale parameter.
- Added `:workout_completed` notification type to the `Notification` schema `@types` list, plus a new migration to update the DB constraint.
- `ExecutionController` placed under the `/athlete_or_admin` pipeline — admins can also execute workouts for testing purposes.
- Execution notes were expanded from one-note-per-exercise quick words into many annotation records per execution, with multi-tag selection and highlighted selected-text anchors in the checklist UI.
- Phase 4 now ships authenticated Phoenix Channels for schedule, notifications, and execution synchronization. The client still fetches authoritative read models over REST, but subscriptions remove the remaining polling/manual-refresh drift from the Phase 3/4 slices.

## Implementation Notes

- Timer sequence traversal now sorts both top-level and nested sections by `order` and emits nested segments depth-first for timed parents instead of only traversing children under untimed containers.
- Execution Mode now treats expanded set entries as distinct checklist steps, advances immediately after the final step in a segment is checked, and persists final-step completion through the normal execution completion API.
- Score capture now accepts free-form score text where needed and no longer allows silently skipping a scoreable transition.
- The post-workout completion screen now exits to the landing page via a stable route instead of browser-history back navigation.
- Scoreable early-complete transitions now lock the timer before opening score capture, and interval-based timer segments clamp their final round to the authored remaining duration.

## Concurrency and Offline Amendment — 2026-07-15

`workout_executions` is a versioned aggregate. Progress commands require an
expected lock version, semantic validation against the materialized timer
sequence, and a stable idempotency operation ID. Conflicts return 409 instead of
overwriting a newer snapshot. Only check-offs may be optimistic; navigation,
pause, resume, score transitions, and completion are committed to client state
after server acknowledgement.

Offline execution uses an ordered IndexedDB mutation log. Reconnection fetches
the authoritative execution, discards already-applied operation IDs, and rebases
remaining check-off intent onto the newest version. The service worker never
serves an authenticated cached response after an origin 401/403 and applies a
bounded TTL to offline reads.
- Execution progress is now persisted as a server-backed state model, not just checked IDs: `status`, `current_segment_index`, `segment_started_at_utc`, `paused_elapsed_ms`, and `resume_countdown_ends_at_utc` are stored in `workout_executions`, rebroadcast over channels, and used for reload recovery and multi-tab synchronization.
- Members now share the same authenticated execution and timer-sequence API surface as athletes/admins, matching the documented Phase 4 audience for `/workouts`.
- Execution starts now require a concrete `master_workout_id`, invalid timer-sequence scale requests return an explicit validation error, and completed executions reject further progress/note mutation to preserve the audit trail.
- The `/workouts` week view now supports mobile swipe navigation, and the service worker caches current workout/execution read requests for the offline-resilience slice defined in the Phase 4 plan.
- Execution progress snapshots are now semantic as well as transport-level: the backend stores `total_elapsed_ms`, per-section elapsed maps, per-segment cycle counters, and auto-derived section score snapshots so interrupted sessions retain meaningful progress even before final completion.
- Timer segments now carry stable `segment_key` identifiers and execution checklist steps are keyed by segment + exercise + set, which prevents repeated rounds or interval segments from colliding on the same exercise ID.
- Completing a scoreable workout no longer depends on manual score entry. The score modal is prefilled with a measured value, the athlete may override it, and if they do not, the backend persists the derived fallback score automatically. For scoreable time-based formats this fixes blank history entries like completed for-time workouts with no submitted score.

## Schedule-Based Timer and Optimistic Progress Amendment — 2026-10-12

Supersedes the "commit after acknowledgement" rule above for execution
progress, and the IndexedDB check-off queue.

- **Timer engine** (`apps/web/src/lib/timer-engine.ts`): pure functions derive
  every clock from the segment's scheduled start, banked pause time and "now".
  When a timed segment ends, the next one starts at the moment it ended
  (`planCatchUp`), not when the client noticed or the server answered, and
  every segment that ran out while the page was hidden is skipped through in
  one step. Ticks use `setInterval` plus `visibilitychange`, because
  `requestAnimationFrame` stops in background tabs.
- **Optimistic progress**: all progress changes apply locally first and are
  sent by `useExecutionSync`, one request at a time, coalescing changes made
  during a request. Failures leave `pendingSync` set and retry; on reload the
  unsynced local state wins while the server `lock_version` is unchanged. A
  409 means another device moved on: its timeline wins (see the conflict
  rebase below).
- **Elapsed accounting**: the client store holds committed time only (segments
  already left). Progress snapshots send committed time plus the current
  segment's banked pause time, and hydration subtracts it again. A pause is no
  longer counted twice, and leaving a segment backwards commits its time.
- **Sequence shape**: segments carry `phase` (`work`/`rest`/`transition`).
  Between-section transitions and rests use synthetic `<id>:transition` and
  `<id>:rest-after` section ids and never count toward section time or scoring.
  Open-ended formats (Death By, EMOM to failure) are one `interval_cycle`
  segment. Round counts may decrease (undo); elapsed totals stay monotonic.
- **Authoring preview**: `POST /admin/workouts/timer-preview` runs the same
  builder on a draft section, so the editor's timeline always matches execution.

## Conflict Rebase, Labels and KPIs Amendment — 2026-10-12 (P2)

- **Conflict rebase** (`apps/web/src/lib/execution-rebase.ts`): the store keeps
  the hand-made marks (check-offs, round counts, scores) as the server last
  acknowledged them. On a 409, or on reload after another device moved on, the
  client adopts the server's clock and position and replays its own unsent
  marks on top: check-offs added or removed, round-count deltas, and scores
  changed locally. The result is resent with the new `lock_version`. This
  restores what the retired IndexedDB queue did for check-offs, now for every
  mark. Check-offs still waiting in that old queue are adopted once on load
  (`legacy-offline-queue.ts`, to be removed after one release).
- **Clock adjustments**: +/-30 s from the pause sheet changes the segment's
  length. It never shortens below what already ran (superseded below: the
  change is now synced).
- **Localized labels**: segments carry `label_key` and `label_params` next to
  the English `label`; clients render the key in the viewer's language and
  fall back to `label` for unknown keys.
- **Free-text timer**: free-text workouts run on the same timer engine, built
  from a preset (format plus durations) that the coach can attach under
  `workout_metadata.free_text_timer`. The clock is persisted per execution in
  `localStorage` as a start timestamp plus banked time, so reloads keep it.
- **KPIs**: progress and completion payloads carry `kpi_counters` (skips,
  countdown skips and segments, pauses and paused time, finish-review opens,
  first start). The API keeps the maximum of each counter, so replays and
  stale snapshots never lower them. `ExecutionKpis.summarize/1` turns those
  counters plus the execution records into the `execution` block of the admin
  analytics summary.

## Synced Adjustments, Free-Text Progress, KPI Dashboard and Class Wall Display — 2026-10-12

- **Clock adjustments are synced.** Progress and completion payloads carry
  `duration_adjustments` (`segment_key → delta seconds`). The API keeps them
  only for countdowns and capped count-ups in the validated sequence (±1 h,
  never below 5 s; unknown keys are dropped so a device can't get stuck) and
  stores each with the authored length and section name. Every device applies
  the server's copy to the authored sequence on load, conflict rebases treat
  them like round deltas, the finish review shows them, and coaches see
  "AMRAP 12: 12:00 → 14:00 (+2:00)" in the athlete's training history.
- **Free-text progress.** Free-text workouts save their clock every 30 s
  while running and on pause/resume/reset/hide, with device KPIs (pauses,
  paused time, resets, first start, review opens). With no timer segments
  the server lets that single clock go back (a reset); structured workouts
  keep monotonic elapsed totals.
- **Where workouts stop.** The server records `kpi_counters.position`
  (format, section, segment, elapsed) and the workout's `formats` on every
  progress write. The KPI report adds stopping points by format and section,
  completion by format and by source, structured vs free text, a daily trend,
  median workout time and the share of workouts whose clock was changed. The
  admin training analytics page shows them (7/30/90 days, table view for the
  trend).
- **Class wall display.** `class_timers` holds one coach-run timer per
  scheduled class (RLS by organization): status, segment, start time (in the
  future during the get-ready countdown), banked pause time, adjustments and
  an optional preset that replaces the class workout (e.g. an EMOM clock for a
  strength class; free-text workouts use their attached preset). The timer is
  a schedule, so timed segments ending need no writes: `ClassTimerMachine`
  (server) and `classTimerPosition` (client) catch up identically, and the
  preset builders are checked against one shared fixture. Coaches/admins send
  commands (`start`, `pause`, `resume`, `next`, `previous`, `jump`, `adjust`,
  `reset`, `finish`, `configure`) with the version they saw; a conflict
  refetches instead of re-sending. Updates are pushed on `class_timer:<class>`;
  any active member of the gym can follow (wall display or phone). Responses
  carry `server_now` so screens correct their own clock skew.
