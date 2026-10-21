# ADR-123: Comprehensive Analytics Instrumentation
Date: 2026-10-12
Status: Accepted

## Context
ADR-015 (Phase 8B) introduced the Analytics context and the `analytics_events`
fact table. It instrumented finance, reviews, injuries and notification
read/click only (TD-011). Workouts, assignments, executions, classes,
messaging and push delivery were not measured. The admin analytics summary
therefore showed nothing for most of the product.

The workout-execution timer audit
(`docs/audits/2026-10-12-workout-execution-timer-audit.md`, on branch
`claude/workout-execution-timer-audit-d8olvm`) lists seven execution KPIs in
§1.3, and it says none of them are measured today. That branch is adding new
execution surfaces in parallel:

- a round counter with "+1 round" and undo (U3, U4)
- a ready screen with a get-ready countdown (U5)
- a pause sheet with resume, restart segment, skip, ±30 s and end (U2, U9)
- adjusting time and rounds while paused (U14)
- landscape/cast mode (U13)
- a reworked finish wizard

Some of these KPIs can only be observed on the client. For example, the server
cannot tell a manual "Next" from an automatic segment advance, and it never
sees a pause sheet open. This work has to provision for those signals without
adding schema or contract churn, and without touching the timer UI files that
branch is rewriting.

Constraints:

- Events are recorded only at write or application boundaries, never in
  controllers or domain modules.
- Every event is tenant-scoped and carries `organization_id`.
- Metadata carries no PII beyond ids and enums.
- An analytics failure must never break the user operation (`call_unsafe`
  semantics).
- No new dependencies.

## Decision
1. **Event registry as allowlist.** `Analytics.Domain.EventCatalog` lists
   every event name (the Phase 8 names plus the ADR-123 families). For each
   event it sets the context type, the subject keys copied into metadata, and
   a dedupe strategy. `Analytics.record_event/1` refuses names that are not
   registered. Metadata is sanitized to scalar values only: strings of 64
   characters or less, integers, floats, booleans, dates and atoms. Maps,
   lists and long strings are dropped, so titles, bodies and notes cannot leak
   into analytics. The registry is code, not a DB check constraint, so adding
   an event type never needs a migration.
2. **Per-tenant dedupe.** The additive migration
   `20261012120000_add_dedupe_key_to_analytics_events` adds a nullable
   `dedupe_key` column. It also adds a partial unique index on
   `(organization_id, event_name, dedupe_key)`. The store inserts with
   `ON CONFLICT DO NOTHING`, so replays become no-ops (`{:ok, :duplicate}`)
   and batch inserts report inserted and duplicate counts. The four dedupe
   strategies are:
   - `:subject`: once per subject id.
   - `:user_subject_day`: once per actor, subject and UTC day.
   - `:explicit`: the caller supplies a namespaced key.
   - none.
3. **One-line instrumentation.** `Application.TrackAnalyticsEvent.call/4`
   takes `(event, actor_context | nil, subject, extra)`. It builds the row
   through the registry and records it with `RecordAnalyticsEvent.call_unsafe/2`.
   It always returns `:ok`. `RecordAnalyticsEvent` now records inside the named
   tenant's `RepoContext` session whenever `organization_id` is known, so
   user-only sessions (executions) and job sessions (push) still satisfy the
   forced RLS policy. Failures emit `[:palee, :analytics, :record_failed]`
   telemetry.
4. **Server-derived execution facts.**
   - Completion facts and the abandon point are pure functions in
     `Execution.Domain.ExecutionAnalytics`.
   - Abandonment is recorded by an hourly Oban cron sweep.
   - A pause count or manual skips cannot be derived from progress snapshots:
     each snapshot overwrites the last, and a segment index advance looks the
     same whether it was automatic or manual. These signals come from the
     ingestion hook below instead.
5. **One provisioning hook for client-only execution signals.**
   `POST /api/executions/:id/interactions` accepts up to 50 events per request
   and is contract-first. It is:
   - allowlisted, with a strict `kind` enum and typed per-kind metadata;
   - idempotent, with a per-event `client_event_id`;
   - owner- and tenant-scoped;
   - rate-limited in its own `execution-interactions` bucket (60 requests per
     minute).

   Events are stored as `execution_interaction` rows. The web helper
   `src/lib/execution-analytics.ts` (`createExecutionAnalytics`) is the client
   API for the timer branch.
6. **Delivery facts without context coupling.** The Notifications context
   emits `[:palee, :notification, :delivered]` telemetry when it creates a new
   in-app notification. `Application.RecordNotificationDelivered`, attached at
   start, records the event in the delivering process. The push dispatch job
   calls `Application.RecordPushDeliveryOutcome`.

## Rationale
- **A registry in code** catches call-site typos in tests. It also lets the
  timer branch extend the vocabulary in one file without a migration.
- **Dedupe keys in the fact table** keep idempotency next to the data. The
  alternatives were Redis or a second table, and either would need its own
  RLS and purge story. The index is partial, so the existing rows and
  un-keyed events cost nothing.
- **One generic ingestion endpoint** with a kind enum, instead of one endpoint
  per surface, means each new timer surface adds an enum value and not a
  route, a controller and a regenerated client.
- **Batching with client ids** fits the offline-first execution model
  (ADR-067). A retried batch is harmless.
- **Telemetry for in-app delivery** keeps the Notifications context
  independent of Application and Analytics (Rule 2). The handler runs
  synchronously in the caller's process, so it sees the caller's sandbox and
  connection. There is no async consumer to reason about.

## Alternatives Considered
- **A DB check constraint on `event_name`.** Rejected. Every new event would
  need a migration, which is exactly the churn the timer branch has to avoid.
- **Deriving pauses and skips from progress updates on the server.** Rejected.
  Snapshots overwrite state, and the server cannot tell an automatic advance
  from a manual "Next". Recording a pause on every progress transition would
  also double count the client's `pause` interaction.
- **Instrumenting controllers or context modules.** Rejected by the
  architecture rules: contexts must not call Application, and controllers
  hold no business logic.
- **A PubSub consumer process for analytics.** Rejected. It is asynchronous,
  which complicates tests (sandbox allowances, eventual assertions), and it
  adds a supervised process for no gain over synchronous telemetry.
- **One endpoint per timer surface.** Rejected because of contract churn (see
  Rationale).

## Consequences
- Every analytics write is best effort. A failing analytics store never fails
  a user operation. `track_analytics_event_test.exs` asserts this.
- `analytics_events.dedupe_key` is dropped from anonymized retained exports,
  because keys can embed user ids (ADR-117).
- The abandonment sweep scans only executions started in the 48 hours before
  the threshold. Abandoned executions older than that at first deploy are not
  backfilled. An execution completed after it was flagged abandoned keeps
  both events. To report "resumed later", join the completed event.
- The first-staff-response latency looks at the last 50 messages of the
  thread. A member run longer than that is measured from the oldest message
  in the window, which makes it a lower bound.
- Push attempts are recorded per attempt, retries included. The `attempt` and
  `final_attempt` metadata distinguish them. Without tenant provenance
  (`organization_id` missing in the job args), nothing is recorded.
- Follow-up debt (only possible with or after the timer branch) is listed in
  Implementation Notes.

## Implementation Notes
Implemented on 2026-10-12 (TD-011).

### Event types and emitting boundaries
All events are recorded best effort, after the primary write succeeds. The
actor is the tenant context unless noted otherwise. `context_id` is the
subject id.

**Workouts** (context type `workout` / `assigned_workout`)

| Event | Boundary | Metadata | Dedupe |
|---|---|---|---|
| `workout_created` | `CreateDraftWorkout` | status, type, authoring_mode | - |
| `workout_published` / `workout_republished` | `PublishWorkout`. "Republished" when assignment or booking targets exist, or a substitution was applied. | type, authoring_mode, is_team_workout, source_workout_id, affected_assignment_count, affected_booking_count, substitution | - |
| `workout_deleted` | `DeleteWorkout` | affected_assignment_count, affected_booking_count, deleted_slot_count | - |
| `workout_duplicated` | `DuplicateWorkout` | source_workout_id, origin (library / assignment / class_slot) | - |
| `workout_assignment_created` | `AssignWorkout` | master_workout_id, scheduled_for, athlete_count | - |
| `workout_assignment_rescheduled` | `RescheduleAssignedWorkout`; the actor is the athlete | master_workout_id, scheduled_for | - |
| `workout_assignment_rejected` | `RejectAssignedWorkout` | - | - |
| `workout_assignment_deleted` | `DeleteAssignedWorkout` | - | - |
| `workout_assignment_opened` | `OpenAssignedWorkout`, through `POST /api/org/:slug/my-workouts/assignments/:id/open`. There is no server read path for a single assignment. The web assignments console calls it when an athlete opens the detail panel. | - | per user, assignment and UTC day |

**Execution** (context type `workout_execution` / `training_log_entry`)

| Event | Boundary | Metadata | Dedupe |
|---|---|---|---|
| `workout_execution_started` | `StartWorkoutExecution` | master_workout_id, source, scale_level_slug | per execution |
| `workout_execution_completed` | `CompleteWorkout` | the above, plus `ExecutionAnalytics.completion_facts/2`: duration_ms, total_elapsed_ms, segment_count, section_count, scoreable_section_count, manually_scored_section_count, auto_scored_section_count, checked_exercise_count, primary_format | per execution |
| `workout_execution_abandoned` | `SweepAbandonedExecutions`, run by the hourly `ExecutionAbandonmentSweepJob` (cron `41 * * * *`, queue `analytics`). Records executions that are not completed and were started at least `:execution_abandonment_hours` ago (default 6). The run is idempotent: already-recorded ids are filtered out first, and the event dedupes on the execution id. | status, plus the abandon point from `abandonment_facts/3`: abandon_segment_index, abandon_format, abandon_segment_kind, segment_count, abandon_progress_pct, total_elapsed_ms, checked_exercise_count, hours_since_start, had_progress_update, minutes_since_last_progress, threshold_hours | per execution |
| `execution_interaction` | `IngestExecutionInteractions`, through `POST /api/executions/:id/interactions` | kind, client_event_id, plus the typed fields allowed for that kind | `user_id:client_event_id` |
| `training_log_entry_logged` | `LogTrainingEntry` | source_type, master_workout_id, workout_type, scale_level_slug, duration_seconds, perceived_effort, section_score_count | per entry; idempotent replays collapse |
| `training_log_entry_voided` | `VoidTrainingLogEntry` | source_type | per entry |

**Scheduling** (context type `class_booking` / `class_attendance` / `scheduled_class` / `class_series`)

| Event | Boundary | Metadata | Dedupe |
|---|---|---|---|
| `class_booking_requested` | `SubmitBooking` | scheduled_class_id, status, auto_approved | per booking |
| `class_booking_approved` / `class_booking_rejected` | `ResolveBooking`; the actor is staff | scheduled_class_id, member_id, has_admin_message | per booking |
| `class_booking_cancelled` | `WithdrawBooking` | scheduled_class_id, cancelled_by=member, previous_status | per booking |
| `class_booking_timed_out` | `TimeoutBooking` (job) | scheduled_class_id | per booking |
| `class_attendance_recorded` | `AdminRecordAttendance` | scheduled_class_id, booking_id, status, member_id | - |
| `class_slot_created` | `CreateScheduledSlot` | class_type_id, master_workout_id, capacity, auto_approve, series_id | - |
| `class_series_created` | `CreateRecurringClassSeries` | class_type_id, master_workout_id | - |
| `class_slot_cancelled` | `DeleteScheduledSlot` | - | - |

**Messaging** (context type `messaging_thread` / `messaging_message`)

All three are recorded by `TrackMessagingAnalytics`. `GetOrCreateMessagingThread`
and `SendMessage` pipe their results through it unchanged.

| Event | Metadata | Dedupe |
|---|---|---|
| `messaging_thread_created` | context_type, participant_count. The user and time are the thread's own creator and `inserted_at`. | per thread |
| `messaging_message_sent` | thread_id, message_type, sender_is_staff. The body is never stored. | per message |
| `messaging_first_staff_response` | thread_id, message_type, response_latency_seconds, pending_member_message_count, from the pure `Messaging.Domain.ResponseLatency` | per message |

**Notifications** (context type `notification`)

| Event | Boundary | Metadata | Dedupe |
|---|---|---|---|
| `notification_in_app_delivered` | `RecordNotificationDelivered`, a telemetry handler attached in `Palee.Application.start/2` | type | per notification |
| `notification_push_outcome` | `RecordPushDeliveryOutcome`, called from `PushDispatchJob` after every dispatcher result. It also writes a `push_dispatch_attempts` row: status, reason class in `error`, SHA-256 of the endpoint. This row feeds the existing summary's `push_dispatch.by_status`. | outcome (sent / expired / failed), reason_class (subscription_expired, not_configured, rate_limited, payload_too_large, client_error, server_error, timeout, unknown), notification_type, attempt, final_attempt | - |

The Phase 8 events are unchanged and are now registered: `payment_recorded`,
`promotion_redeemed`, `referral_*`, `finance_*`, `review_submitted`,
`injury_reported`, `injury_healed`, `notification_read`, `notification_clicked`.

### Interaction kinds (`execution_interaction.metadata.kind`)
The allowlist lives in `Analytics.Domain.ExecutionInteraction`. The OpenAPI
`kind` enum is generated from it, and a ConnCase test keeps the metadata
schema keys identical to it.

Typed metadata fields:

| Field | Type |
|---|---|
| `segment_index` | integer, 0 to 10 000 |
| `section_id` | token |
| `format` | token |
| `surface` | enum: pause_sheet, primary_action, header, gesture, keyboard, snackbar, ready_screen, finish_wizard, cast_display, lock_screen |
| `round_count` | integer |
| `delta_rounds` | integer, ±100 |
| `delta_seconds` | integer, ±3600 |
| `elapsed_ms` | integer |
| `remaining_ms` | integer |
| `duration_ms` | integer |
| `countdown_seconds` | integer |
| `step` | integer |
| `scored_section_count` | integer |
| `enabled` | boolean |
| `orientation` | enum: portrait, landscape |
| `cue_channel` | enum: sound, voice, vibration |

Kinds and the fields each one accepts:

| Kind | Allowed fields |
|---|---|
| `pause` | position*, elapsed_ms |
| `resume` | position*, duration_ms (how long it was paused) |
| `segment_skipped` | position*, elapsed_ms, remaining_ms |
| `segment_restarted` | position*, elapsed_ms |
| `round_incremented` / `round_decremented` | position*, round_count |
| `check_off_undone` | position* |
| `time_adjusted` | position*, delta_seconds |
| `rounds_adjusted` | position*, delta_rounds, round_count |
| `ready_screen_shown` | format, surface |
| `workout_launched` | format, surface, countdown_seconds |
| `first_segment_started` | segment_index, section_id, format, duration_ms (time from launch) |
| `finish_wizard_opened` | surface, segment_index |
| `finish_wizard_saved` | step, duration_ms, scored_section_count |
| `finish_wizard_abandoned` | step, duration_ms |
| `cast_mode_toggled` | enabled, orientation, surface |
| `cues_toggled` | enabled, cue_channel, surface |

\* position = segment_index, section_id, format, surface.

Validation rules:

- `occurred_at` must be within the last 7 days and at most 5 minutes in the
  future.
- Any invalid event rejects the whole batch with a 422 that lists
  `{index, reason}` for each failing event.
- Duplicate client ids inside one batch collapse.

To add a kind, add it to `@kinds_fields` (and a new typed field to `@fields`
if needed), add the property to `ExecutionController`'s metadata schema, and
regenerate the client. No migration is needed.

### Timer audit §1.3 KPI mapping
| KPI | Source |
|---|---|
| Start → finish completion rate | `workout_execution_completed` / `workout_execution_started` (both deduped per execution) |
| Abandon point | `workout_execution_abandoned`.metadata `abandon_format`, `abandon_segment_index`, `abandon_progress_pct` (server-derived from the last snapshot) |
| Score capture rate | `workout_execution_completed`.metadata `manually_scored_section_count` / `scoreable_section_count`. The client may also send `finish_wizard_saved.scored_section_count`. |
| "Next"-tap rate on countdown segments | `execution_interaction` kind `segment_skipped` (client), divided by countdown segments from the completion facts or the timer sequence |
| Pause frequency and duration | kinds `pause` (count) and `resume.duration_ms` (duration), per execution (`context_id`) |
| Time-to-first-rep | kind `first_segment_started.duration_ms`, or `workout_launched` → `first_segment_started` `occurred_at` delta |
| Finish-wizard drop-off | kinds `finish_wizard_opened` vs `finish_wizard_saved` / `finish_wizard_abandoned` |

### Upcoming surfaces and what the timer branch must call
Once merged, the timer branch creates one tracker per execution session and
disposes it on unmount or finish:

```ts
const analytics = createExecutionAnalytics({
  executionId,
  getToken: () => tokens?.access_token,
});
// ...
await analytics.dispose();
```

Then it calls `analytics.track(kind, metadata)` at these points:

| Surface | Call |
|---|---|
| U3 round counter | `track("round_incremented", { segment_index, format, round_count, surface: "primary_action" })` on "+1 round"; `track("round_decremented", {...})` on the "–1" undo |
| U4 check-off undo | `track("check_off_undone", { segment_index, section_id })` |
| U5 ready screen and get-ready | `track("ready_screen_shown", { format })` when the ready screen renders; `track("workout_launched", { countdown_seconds })` on Start; `track("first_segment_started", { segment_index: 0, format, duration_ms: msSinceLaunch })` when the countdown ends |
| U9 / U2 pause sheet | `track("pause", { segment_index, elapsed_ms, surface: "pause_sheet" })`; `track("resume", { segment_index, duration_ms: pausedMs })`; `track("segment_restarted", {...})`; `track("segment_skipped", { segment_index, elapsed_ms, remaining_ms, surface: "pause_sheet" })`. A manual "Next" on a countdown segment outside the sheet uses `segment_skipped` with `surface: "primary_action"`; automatic advances send nothing. "End workout" opens the finish wizard (below). |
| U14 adjust on the fly | `track("time_adjusted", { segment_index, delta_seconds: ±30 })`; `track("rounds_adjusted", { segment_index, delta_rounds, round_count })` |
| U13 landscape / cast | `track("cast_mode_toggled", { enabled, orientation, surface: "cast_display" })` |
| Finish wizard | `track("finish_wizard_opened", { surface, segment_index })`; `track("finish_wizard_saved", { step, duration_ms, scored_section_count })` on save; `track("finish_wizard_abandoned", { step, duration_ms })` on "Back to workout" or dismissal |
| U1 cues | `track("cues_toggled", { enabled, cue_channel })` |

The server already records execution start, completion (with score capture),
abandonment and training-log entries, so the timer branch must not send those.

### Deviations and emergent decisions
- **Push outcomes go to two places.** They are written both to the existing
  (previously unused) `push_dispatch_attempts` fact table and as an analytics
  event, so the admin summary's push section finally shows data.
- **Fix to the `workout_rejected` notification.** The notification always
  crashed on assignments' ISO date strings. It is fixed here because the
  rejection instrumentation exercises that path. Its payload also lacks
  `organization_id`, so staff recipients still resolve to none. That is
  logged as follow-up.
- **Own rate-limit bucket for ingestion.** The interaction endpoint sits in
  its own scope so analytics flushes never consume the 240/min
  progress/complete budget.

### Follow-up debt (needs the timer branch or later work)
- Wire `createExecutionAnalytics` into ExecutionMode, the pause sheet, round
  counter, ready screen, finish wizard and cast mode, as listed in the table
  above. This lands with or after the timer branch merge. The generated
  `openapi.json` and `schema.ts` will conflict mechanically; resolve by
  regenerating.
- Admin analytics UI: KPI tiles and charts for the new event families.
  `analytics_summary.events.by_name` already counts them.
- Backfill abandonment for executions older than the sweep window, if
  historical numbers are wanted.
- `workout_rejected` notification payload: add `organization_id` so staff are
  actually notified.
- Persist the interaction queue (IndexedDB, like the offline progress queue)
  if offline sessions longer than a page lifetime must keep their signals.
