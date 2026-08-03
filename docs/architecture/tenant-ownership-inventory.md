# Tenant Ownership Inventory

Date: 2026-08-03
Status: Baseline for ADR-055 through ADR-060

This inventory classifies persisted and infrastructure resources before tenant
backfill. `Tenant-owned` resources require an `organization_id`. `Global-personal`
resources require an `owner_user_id` (or their existing user key) and explicit
sharing. `Platform-global` resources are deliberately shared and never become
shared merely because an organization key is absent.

## PostgreSQL

| Context | Resources | Classification | Migration rule |
|---|---|---|---|
| Organizations | `organizations`, `organization_memberships`, `registration_invitations`, `organization_domains`, `organization_settings` | Tenant-owned, except `organizations` is the tenant root | Already explicit |
| Identity | `users` | Global-personal authentication principal | Keep globally unique credentials; memberships carry tenant roles |
| Workouts | `master_workouts`, `workout_folders`, `workout_sections`, `workout_exercises`, `exercise_variations`, `assigned_workouts`, `assigned_workout_athletes` | Tenant-owned | T4 Workouts |
| Workouts | `scale_levels` | Platform-global initially | Tenant overrides require a later explicit model |
| Scheduling | `class_types`, `scheduling_settings`, `class_series`, `scheduled_classes`, `bookings`, `class_attendance_records` | Tenant-owned | T4 Scheduling |
| Execution | `workout_executions`, `execution_progress_operations` | Global-personal actual history with organization provenance when prescribed by a tenant | T4 Execution; never grant access from provenance alone |
| Gamification | `seasonal_challenges`, `user_challenge_progress`, `challenge_leaderboard_opt_ins`, `leaderboard_opt_ins`, `gamification_settings` | Tenant-owned | T4 Gamification |
| Gamification | `user_stats`, `user_achievements`, `user_gamification_preferences` | Global-personal unless a projection is explicitly organization-scoped | Split personal facts from tenant projections in T4 |
| Pantheon | `user_pr_records`, `user_pr_history` | Global-personal | Preserve self-authored PR ownership; tenant leaderboards are projections |
| Finance | `membership_packages`, `memberships`, `membership_package_subscriptions`, `membership_payments`, `promotion_campaigns`, `promotion_codes`, `promotion_redemptions`, `referral_programs`, `referral_events`, `referral_rewards`, `finance_invoices`, `finance_invoice_lines`, `finance_payment_reversals`, `finance_credit_ledger_entries`, `finance_entitlement_usage_entries`, `finance_settings` | Tenant-owned | T4 Finance |
| Wellbeing | Self-authored rows in `injury_reports` and their `injury_status_events` | Global-personal | Add owner and optional provenance |
| Wellbeing | Organization-authored safety rows in `injury_reports` and their events | Tenant-owned | Split by authorship before backfill |
| Feedback | `review_questionnaires`, `reviews`, `review_answers` | Tenant-owned | T4 Feedback |
| Messaging | `messaging_threads`, `messaging_participants`, `messaging_messages` | Tenant-owned for organization conversations; personal direct messaging needs an explicit personal classification | T4 Messaging |
| Analytics | `analytics_events`, `notification_click_events`, `push_dispatch_attempts`, legacy `attendance_records`, `communication_threads`, `communication_messages` | Tenant-owned when sourced from tenant activity; global-personal when sourced from personal activity | Store ownership class with the event |
| Analytics | `exercise_catalog_entries` | Platform-global canonical movement catalog | Tenant proposals and aliases stay tenant-owned until promotion |
| Notifications | `notifications` | Ownership follows source: tenant-owned or global-personal | Persist source ownership class |
| Notifications | `push_subscriptions` | Global-personal device registration | Delivery payload still carries source ownership |
| Notifications | `notification_push_settings` | Platform-global installation setting | Platform-operator only |
| Coaching | `admin_athlete_notes` | Tenant-owned | T4 Coaching |
| Compatibility | `assignment_messages` | Removed legacy table | No backfill |
| Oban | `oban_jobs`, `oban_peers` | Platform operational | Tenant/user ownership belongs in validated job args and uniqueness keys |

## Materialized Views

| Resource | Classification | Required scope |
|---|---|---|
| `finance_aggregates` | Tenant-owned | Group and filter by `organization_id` |
| `coaching_aggregates` | Tenant-owned | Group and filter by `organization_id` |
| `weekly_leaderboard` | Tenant-owned projection | Partition and query by `organization_id`; source PR facts remain personal |

## Jobs

Tenant-owned jobs: booking timeout/notification/release, class-series extension,
finance overdue/reminder/entitlement reconciliation, finance/coaching aggregate
refresh, organization message dispatch, and tenant notification dispatch.

Global-personal jobs: nickname propagation, personal PR search sync, and personal
workout-completion projections. A completion triggered by tenant programming carries
both `owner_user_id` and organization provenance. Cron launchers are platform-global
but must fan out into explicitly scoped work.

Every tenant-owned job argument and uniqueness key must include `organization_id`.
Every personal job must include `owner_user_id`. Missing scope is rejected rather
than interpreted as global.

## Realtime, Cache, Search, And Storage

| Boundary | Existing resources | Classification and target key |
|---|---|---|
| PubSub/Channels | schedule, booking, chat, execution, notification, sync, workout events | Tenant events: `org:{organization_id}:...`; personal events: `user:{owner_user_id}:...`. Execution topics require owner authorization plus optional provenance. |
| Redis | `landing:{user_id}`, refresh-token revocation, rate-limit keys | Landing and session keys are global-personal. Tenant read-model keys add `org:{organization_id}`. Rate-limit keys are platform-security metadata and must not contain invitation tokens. |
| Meilisearch | member index, PR index | Member documents are tenant-owned and filtered by organization. PR documents are global-personal and filtered by owner/grant. Canonical movements are platform-global; aliases are tenant-owned. |
| MinIO | `avatars/{user_id}/...`, invoice/document keys | Avatars are global-personal. Tenant invoices/documents use `organizations/{organization_id}/...`; personal exports use `users/{owner_user_id}/...`. |
| Calendar/CSV/document exports | signed calendar feeds, invoices, generated reports | Bind tenant exports to organization and membership; bind personal exports to owner and explicit grant. |

## Migration Gates

- Expand/backfill/enforce/contract runs one bounded context at a time.
- Backfill reports count tenant-owned, global-personal, platform-global, and unmapped
  records separately.
- No independent organization is provisioned until the relevant T4/T5 isolation
  loop and two-tenant tests pass.
- Automated invitation delivery remains deferred as `TD-034`.
