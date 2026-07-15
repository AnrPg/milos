# ADR-020: Referral Reward and Coaching Refresh Hardening
Date: 2026-06-12
Status: Accepted

## Context

Phase 8 referral programs model reward policy as configurable Finance domain
data, but reward application still routes every applied reward through a
credit-ledger grant. That makes non-credit rewards (`discount`, `free_period`,
and `manual`) creatable but not fulfillable. Referral event creation also
accepts raw user IDs without validating that the referrer and referred users are
eligible public-account roles or that member conversions are represented by a
real membership.

The Coaching read model also has two drift risks. The materialized view counts
every athlete account as active even when the same athlete is also counted as
inactive, and coaching aggregate refresh is operationally coupled to Finance
aggregate refresh through a single worker.

## Decision

Referral reward application will dispatch through a Finance domain fulfillment
policy by `reward_type`. Credit rewards create an idempotent credit-ledger grant
and require a positive amount. `discount`, `free_period`, and `manual` rewards
are marked applied without creating a credit-ledger entry; their fulfillment is
represented by the reward status and audit params until a later product-specific
redemption surface consumes them.

Referral eligibility will be validated before persistence. Referrers must be
member or athlete accounts. Referred users must be member or athlete accounts.
Admins cannot participate in referral lifecycle rows. New referral events must
include a membership that belongs to the referred user, making the event a real
member conversion instead of an arbitrary user pair.

Coaching aggregate semantics will define active athletes as athlete accounts
with a completed workout in the last 14 days. Inactive athletes are athlete
accounts without that recent completion. The average completion rate denominator
will use the total athlete count while the dashboard count label remains active.

Finance and Coaching aggregate refresh will use separate workers and cron
entries so either bounded context can refresh independently if the other fails.

## Rationale

Keeping fulfillment dispatch in the Finance domain preserves the configurable
reward taxonomy without forcing every reward type through credit accounting.
The Ecto adapter remains responsible for persistence side effects, but it now
asks a pure domain policy which side effect, if any, is valid for the reward.

Requiring public account roles and referred membership ownership prevents admin
IDs and unrelated users from creating finance lifecycle facts. The application
service can enrich role snapshots through the Identity public API without
importing Identity schemas into Finance.

Splitting refresh workers keeps bounded-context operational failure isolated
while preserving the existing Oban analytics queue.

## Alternatives Considered

Removing non-credit reward types:
rejected because the schema, program policy, and admin authoring surface already
support the full taxonomy and manual/free-period rewards are legitimate gym
operations.

Creating immediate invoice/payment effects for discounts and free periods:
rejected because no concrete invoice-redemption workflow exists yet. Marking
the reward applied gives admins an auditable lifecycle without inventing hidden
accounting semantics.

Counting all athlete accounts as active and renaming the dashboard label:
rejected because the specification calls inactive athletes an alert segment in
coaching analytics.

Keeping one aggregate refresh worker with independent `case` branches:
rejected because a single job retry policy still couples Finance and Coaching
operationally.

## Consequences

Credit rewards remain the only referral reward type that mutates the credit
ledger. Applied non-credit rewards are fulfilled by lifecycle status only and
must be interpreted by future discount/free-period/manual operational workflows.

Referral event creation now requires membership-backed referred member
conversion data. Admin-created referral rows without a membership are rejected.

The existing materialized view definition is replaced by a new migration so
Coaching metrics match dashboard semantics. Finance and Coaching refresh jobs
will have separate Oban retry histories.

## Implementation Notes

Implemented on 2026-06-12.

Referral reward fulfillment now uses
`MilosTraining.Finance.Domain.ReferralRewardFulfillment` to dispatch by reward
type. Credit rewards create the existing idempotent credit-ledger grant and
still require a positive amount. `manual`, `discount`, and `free_period`
rewards now apply successfully as lifecycle-only fulfillment and do not create
credit-ledger entries.

Referral event creation now requires the referred user's membership. The admin
API application service enriches requests with referrer/referred role snapshots
through the Identity public API, while Finance domain policy rejects admin or
unknown participant roles. The admin Finance UI now selects referral
participants from the existing member search results and auto-fills the
referred membership instead of asking admins to type raw user IDs.

The Coaching materialized view is recreated by
`20260612160000_fix_coaching_active_athlete_aggregate_semantics.exs`. Active
athletes are athletes with a workout completion in the last 14 days; inactive
athletes are athletes without one. A Coaching integration test refreshes and
reads the materialized view through the public Coaching API to lock that
semantic contract.

Finance and Coaching aggregate refresh now use separate workers:
`RefreshFinanceAggregatesJob` and `RefreshCoachingAggregatesJob`. Oban cron
registers both jobs on the analytics queue, giving each bounded context its own
retry/failure fate.

Admin coaching note UI copy now reports that notification delivery will be
attempted, matching the best-effort notification side-effect boundary.

Verification completed:

- `DB_PORT=5434 MIX_BUILD_PATH=/tmp/milos_api_build_adr20 mix test test/milos_training/finance/domain/referral_policy_test.exs test/milos_training/finance/domain/referral_reward_fulfillment_test.exs test/milos_training/finance/finance_test.exs test/milos_training/coaching/coaching_test.exs test/milos_training/workers/aggregate_refresh_job_test.exs test/milos_training_web/controllers/phase8_finance_controller_test.exs`
- `MIX_BUILD_PATH=/tmp/milos_api_build_adr20 MIX_ENV=test mix milos.export_openapi ../web/src/api/generated/openapi.json`
- `npx openapi-typescript src/api/generated/openapi.json -o src/api/generated/schema.ts`
- `npm run lint`
- `npm run build`
- `DB_PORT=5434 MIX_BUILD_PATH=/tmp/milos_api_build_adr20 mix test`

The full API suite passed with 224 tests and 0 failures. Frontend lint and the
Next.js production build passed.
