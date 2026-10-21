# ADR-133: Atomic Organization Provisioning and Tenant-Scoped Workout Reads
Date: 2026-10-13
Status: Accepted

## Context
ADR-128 made scale levels tenant-owned and had `Application.ProvisionOrganization`
seed the defaults *after* `Organizations.provision_organization/3` committed:
two transactions in two contexts. A failure between them left a gym with no
scale levels. The other way a gym comes into existence, an owner creating
another gym (`OwnerOrganizationActions.create/3`, ADR-099), did not seed scale
levels at all.

Separately, `Workouts` still exported context-free read arities
(`get_workout/1`, `list_workouts/0`, `get_assignment/1`,
`materialize_workout_for_scale/2`, ...). They read in whatever RepoContext
session the caller happened to have open. Since master workouts and
assignments have forced RLS with no legacy fallback, outside an open tenant
session they silently returned `nil`/`[]` in production (for example the
gamification projection job's workout lookup and the assignment change
targets that `DeleteWorkout` / `PublishWorkout` notify), while the superuser
test role still saw rows. TD-094 tracked both.

## Decision
1. **Gym creation and its defaults are one transaction.**
   `Organizations.provision_organization/3` and
   `Organizations.create_owned_organization/3` take a `seed_defaults` option, a
   `(%{organization_id, user_id} -> {:ok, term} | {:error, term})`.
   `Organizations.Commands.SeedTenantDefaults` runs it inside the creation
   transaction, in the new organization's `RepoContext` (the organization row
   itself stays a system insert). An error, or a raise, rolls back the
   organization, settings, invitation/provisioning event or owner membership,
   and anything the seed wrote.
2. **The Application layer says what the defaults are.**
   `Application.TenantDefaults.call/1` is the single list of per-tenant
   defaults (today `Workouts.seed_default_scale_levels/1`).
   `Application.ProvisionOrganization` (vendor) and the new
   `Application.CreateOwnedOrganization` (owner) hand it to Organizations.
   `OwnerOrganizationController.create` goes through the application service.
3. **Every Workouts read takes a tenant context.** The context-free read
   arities are removed from `Palee.Workouts`, from the
   `Workouts.WorkoutStore` facade and from the `Workouts.Queries.*` modules.
   Reads that had no scoped form gain one:
   `list_workout_change_targets/2`, `get_assignment/2`, `exercise_exists?/2`,
   `materialize_workout/2`, `materialize_workout_for_scale/3`.

## Rationale
- Organizations stays ignorant of Workouts (no compile dependency, the
  architecture gate is unchanged) while still owning the transaction and the
  RLS sequencing it already handled for the owner membership. The Application
  service only composes context APIs and holds no Repo.
- A callback is the narrowest transactional API: no generic "run anything in
  a transaction" port leaks out of a context, and the scope the seed runs in
  is decided by the context that knows the new organization id.
- Passing the tenant context explicitly makes a read's scope visible at the
  call site and fail-closed, instead of depending on ambient session state.

## Alternatives Considered
- **Keep two transactions and retry/compensate** (delete the org on seed
  failure): a compensating delete can itself fail and the organization is
  briefly visible without defaults.
- **A cross-context `Application.Transaction` helper wrapping `Repo`**:
  violates "no Repo in Application services" and would make every context's
  writes implicitly joinable.
- **Organizations calls `Workouts.seed_default_scale_levels/1` itself**:
  a cross-context dependency from a core context to a feature context.
- **Seed lazily on first scale-level read**: a read with write side effects,
  and every consumer (DSL preflight, authoring, execution) would need it.
- **Keep the context-free reads for "internal" callers**: they were exactly
  the callers returning empty data under RLS.

## Consequences
- A provisioning or owner-create request either yields a gym with its default
  scale levels or no gym at all. Future per-tenant defaults are added to
  `TenantDefaults` only.
- Owner-created gyms now start with default scale levels, like vendor-
  provisioned ones.
- `ADR-128`'s "Provisioning is two transactions" consequence no longer holds.
- Context-free application arities that only existed to call the removed
  reads are gone or fail closed with `{:error, :organization_context_required}`
  (`DeleteWorkout.call/1`, `PublishWorkout.call/2`, `GetPublishedWorkout.call/1`,
  `GetAdminWorkout.call/1`, `GetMaterializedWorkout.call/1`,
  `ListAdminWorkouts.call/0`, `GetWorkoutDslAuthoring.call/1`,
  `DuplicateWorkout.call/1,2`, `RescheduleAssignedWorkout.call/3`,
  `GetCoachingAthleteDrillDown.call/1,2`, `GetAdminUserCoachingContext.call/1,2`,
  `GetAdminUserTrainingHistory.call/1`). Assignment message threads need a
  tenant context, like class-slot threads already did.
- Context-free *write* arities remain in `Workouts` / `WorkoutStore` for the
  legacy commands; they run in the caller's session (follow-up).

## Implementation Notes
- `OrganizationStore.transaction/1` joins an enclosing transaction when one is
  open (unchanged); a seed error then propagates to the caller, which owns the
  outer rollback. The provisioning store's `Ecto.Multi` runs nested inside it.
- The `WorkoutStore` facade no longer declares `@behaviour
  Workouts.Ports.WorkoutStore`: the port is the session-scoped adapter
  contract (unchanged), the facade is where the tenant session is opened and
  its public surface is now the scoped one. `workout_organization_id/1` stays
  deliberately un-scoped (F-03 tenant derivation, followed by a membership
  check). `Queries.ListWorkouts` (unused) was deleted.
- Migrated callers read in the tenant they already had or could derive:
  executions use their own `organization_id` (`CompleteWorkout`,
  `UpdateExecutionProgress`, `SubmitExecutionNote`, `SweepAbandonedExecutions`,
  `StartExecution`); `GetWorkoutTimerSequence` materializes the workout it
  already read instead of re-reading it; the completion projection's workout
  lookup now reads each completion's workout in that completion's
  organization (it ran with no tenant session and found nothing under RLS);
  `DeleteWorkout` / `PublishWorkout` list assignment change targets in the
  acting tenant (previously unscoped, so empty under RLS: assignees were not
  notified); `GetAdminUserTrainingHistory` reads assigned workouts through the
  tenant-scoped drill-down; `ListWorkoutExecutions` shows an execution whose
  organization cannot be resolved as "Deleted workout" rather than reading
  unscoped; `SubmitReview` treats workout/exercise targets without a tenant
  as not found; `InjuryWarningEvaluation` reads the workout with the
  evaluation's context.
- `GetOrCreateMessagingThread` gained a tenant clause for assignment threads
  and writes the thread inside `Messaging.with_tenant_context/2`.
- No migration, OpenAPI or web change.
- Tests: `Organizations.AtomicOrganizationCreationTest` (seed runs in the new
  tenant's scope; a failing seed rolls back vendor provisioning and owner
  creation; RLS enforced), `Application.OrganizationCreationDefaultsTest`
  (both flows seed default scale levels), owner controller test asserts the
  new gym's levels, `Workouts.TenantScopedReadsTest` (two-tenant isolation of
  the new scoped reads and absence of the context-free arities).
- Deferred: removing the remaining context-free *write* arities from
  `Workouts` / `WorkoutStore` and their legacy `Workouts.Commands.*` callers.
