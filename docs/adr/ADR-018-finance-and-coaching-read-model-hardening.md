# ADR-018: Finance and Coaching Read Model Hardening
Date: 2026-06-12
Status: Accepted

## Context

The Phase 8 Finance and Coaching implementation exposed several correctness and
operability gaps across domain policy, persistence, application services, API
contracts, and admin/member UI.

Custom package renewals could produce zero-length periods, package entitlement
ignored package activity and subscription dates, promotion redemption limits
were checked without serialization, and promotion analytics summed incompatible
discount units. Finance data existed but was not composed into the landing page.
Referral programs had no management workflow and did not control reward policy.
The revenue read model was row-limited instead of month-limited.

The `coaching_aggregates` materialized view also had no Coaching-owned query
port, public API, application service, or refresh lifecycle. The admin analytics
dashboard consequently labelled unrelated cross-context totals as coaching
analytics. Finally, coach-note success was incorrectly coupled to notification
delivery after the note had already been persisted.

## Decision

Finance and Coaching hardening will use the following rules:

- Billing periods remain the closed taxonomy `monthly`, `quarterly`, `annual`,
  and `custom`. Custom renewal invoices require an explicit service-period end
  later than the start. Unknown periods are rejected rather than silently
  producing a zero-length period.
- Package assignment requires an active package. Active subscription reads,
  entitlement, and renewal selection require `starts_on <= today` and either no
  `ends_on` or `ends_on >= today`.
- Promotion-code redemptions run in a database transaction that locks the code
  row before rechecking campaign/code lifecycle and redemption count.
- Finance aggregates report promotion counts by discount type and realized
  monetary discount separately. Percentage, free-period, and manual configured
  values are never summed into a currency total.
- The landing-page application service composes a member-safe Finance public
  read model and exposes package, last payment, expiry, and entitlement fields.
- Referral programs gain Finance query, application, OpenAPI, controller, and UI
  surfaces. Referral events require an active program, and reward creation
  snapshots the selected program's configured reward type and value.
- Finance summary returns a 24-calendar-month revenue series aggregated across
  all package and user-type rows for each month.
- Coaching owns a store port, query, public API, and application service for
  `coaching_aggregates`. The scheduled analytics refresh lifecycle refreshes
  both Finance and Coaching materialized views through their public commands.
  Cross-context review, wellbeing, and telemetry totals remain separately
  labelled.
- Coach-note persistence is the primary write. Notification enqueue or fallback
  failure is logged but does not change the successful note result.
- Promotion campaign dates and percent limits are validated in Finance
  changesets and represented in the authoring API/UI.

## Rationale

These decisions preserve the existing hexagonal boundaries and ADR-017's
explicit custom-period contract while eliminating silent fallbacks. Row locks
serialize the only mutable promotion capacity boundary without introducing a
new counter table or raw SQL mutation.

Read models remain owned by their source contexts. Application services compose
Finance, Coaching, Analytics, Feedback, and Wellbeing maps without importing
foreign schemas. Materialized views continue to provide bounded dashboard reads,
but their refresh and query lifecycles are now reachable through context ports.

## Alternatives Considered

Storing a custom interval length on packages:
rejected because ADR-017 already defines custom renewal periods by explicit end
date, and changing that contract would require new product semantics.

Enforcing promotion limits with a mutable redemption counter:
rejected because it duplicates the redemption ledger and requires reconciliation
after failed writes. Locking the code row serializes count-and-insert against the
authoritative rows.

Converting every discount to money at redemption time:
rejected because percent and free-period discounts do not have a reliable
monetary value unless linked to an actual payment or invoice. Only realized,
linked currency offsets are reported as money.

Reading `coaching_aggregates` from the generic Analytics context:
rejected because the materialized view is the specified Coaching read model and
must be owned and exposed by Coaching.

Returning an error when note notification fails:
rejected because the note has already committed and the design document
explicitly defines notification as a non-critical secondary effect.

## Consequences

Custom renewal requests must supply `service_period_end`. Existing package and
subscription rows remain compatible because no column type or destructive table
change is required.

Promotion redemption throughput is serialized per code, while unrelated codes
can still redeem concurrently.

The finance aggregate materialized view is recreated additively by a new
migration. API clients gain new fields and routes; generated client artifacts
must be regenerated rather than edited manually.

Referral events created through the supported workflow are program-backed.
Legacy rows with a null program remain readable but cannot derive a new reward
until assigned to a program through a future correction workflow.

## Implementation Notes

Implemented across the Finance domain, commands/queries, public context API,
store port, Ecto adapter, application services, OpenAPI controllers, generated
client artifacts, and admin/member UI.

Finance package periods are now validated as the closed billing-period
taxonomy, with custom renewal periods requiring an explicit end date later than
the start date. Package assignment rejects inactive packages, and entitlement
and renewal queries only consider subscriptions whose active status is valid for
today's date window.

Promotion code redemption now locks the promotion code row inside the
transaction before rechecking code/campaign lifecycle and redemption capacity.
Promotion campaign/code authoring validates campaign date order, active flags,
max redemption limits, and percentage discounts at or below 100.

The finance aggregate materialized view was recreated to separate promotion
redemption counts by discount type and realized monetary discount cents. The
finance summary query now returns a 24-calendar-month revenue series rather
than a row-limited aggregate slice.

Landing-page membership data is composed through the Finance public API and
returns member-safe package, payment, expiry, and entitlement fields. Referral
programs now have list/create ports, application services, admin API routes,
OpenAPI request bodies, and UI management. Referral events require an active
program and reward creation snapshots reward type/value from that program.

Coaching now owns the `coaching_aggregates` query/refresh port and public API.
The shared aggregate refresh worker refreshes Finance and Coaching through
their context commands, and the admin analytics dashboard labels Coaching data
separately from cross-context review, wellbeing, and telemetry totals.

Admin athlete note writes now treat notification enqueue/fallback delivery as a
non-critical side effect. Delivery failure is logged and the persisted note is
still returned successfully, preventing duplicate notes on retry.

Additional hardening completed on 2026-06-12:

- Invoice lifecycle now derives `overdue` before `partially_paid` whenever an
  invoice still has a remaining balance past its due date. Finance entitlement
  reads count overdue invoices from due date plus balance rather than relying
  only on the stored status label.
- Finance read paths no longer refresh persisted projections. Member profile
  reads compute live entitlement data without rewriting membership timestamps,
  and operational queues compute overdue invoice display status without
  persisting invoice status changes from GET requests.
- Admin finance search now returns a bounded membership/package summary
  projection instead of loading full member profiles, invoices, payments,
  credits, and redemptions for every non-admin user. Empty initial searches
  return no rows.
- Admin analytics passes the dashboard reporting window into Finance so paid
  revenue is scoped to the same period as Analytics, Feedback, and Wellbeing
  flow metrics.
- Review submission now server-authors immutable target snapshots after
  validating the target through the owning public context. Caller-provided
  snapshots are ignored, and the public review request contract no longer
  accepts `target_snapshot`.
- Review moderation now supports `needs_follow_up` and triage tags through the
  application service, feedback store, admin API contract, and admin UI.
- Admin review and injury lists now support `limit`/`offset` query parameters
  and UI pagination so older records remain reachable.
- Attendance recording validates that a supplied booking belongs to the same
  user and scheduled class through the Scheduling public API before writing the
  Analytics attendance projection.

Verification completed:

- `MIX_ENV=test mix milos.export_openapi ../web/src/api/generated/openapi.json`
- `npx openapi-typescript src/api/generated/openapi.json -o src/api/generated/schema.ts`
- `npm run lint`
- `npm run build`
- `DB_PORT=5434 mix test test/milos_training/finance/finance_test.exs test/milos_training_web/controllers/admin_analytics_controller_test.exs`
- `DB_PORT=5434 mix test`

The full API suite passed with 215 tests and 0 failures. Frontend lint and the
Next.js production build passed. The remaining SQL sandbox and npm audit notes
are tracked in `docs/technical_debt.md` as TD-018 and TD-019.

Additional verification for the 2026-06-12 hardening pass:

- `MIX_BUILD_PATH=/tmp/milos_api_build mix compile`
- `DB_PORT=5434 MIX_BUILD_PATH=/tmp/milos_api_build mix test test/milos_training/finance/domain/invoice_lifecycle_test.exs test/milos_training/finance/finance_test.exs test/milos_training/feedback/feedback_test.exs test/milos_training/analytics/analytics_test.exs test/milos_training/application/admin_search_users_test.exs`
- `MIX_BUILD_PATH=/tmp/milos_api_build mix milos.export_openapi ../web/src/api/generated/openapi.json`
- `pnpm exec openapi-typescript src/api/generated/openapi.json -o src/api/generated/schema.ts`
- `pnpm lint`
- `pnpm exec tsc --noEmit`
