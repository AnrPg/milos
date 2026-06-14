# Phase 8 Finance, Packages, Promotions, and Referrals
Date: 2026-06-11
Status: Planning anchor

## Purpose

This note records the expanded Phase 8 Finance scope. The dashboard needs real
financial analytics, so membership, package, promotion, referral, and payment
data must be modeled as first-class domain facts rather than UI-only fields.

## Architectural Direction

Add a dedicated `MilosTraining.Finance` bounded context.

The context owns:
- Membership package definitions.
- User membership state.
- Package subscriptions.
- Payments and payment history.
- Promotion campaigns and promotion codes.
- Promotion redemptions.
- Referral incentive programs.
- Referral events and rewards.
- Financial aggregate reads.

Finance should store `user_id` references and role/type snapshots, but Identity
remains the source of truth for current user role.

## Core Entities

### `membership_packages`

Admin-managed package/scheme objects. These are not strings in a list.

Suggested fields:
- `id`
- `code`
- `name`
- `description`
- `family`: unlimited, limited-visits, personal-programming, hybrid, custom
- `billing_period`: monthly, quarterly, annual, custom
- `base_price_cents`
- `currency`
- `tags`
- `params`: structured map for visits, remote programming, class access, coaching touchpoints, future entitlements
- `active`
- timestamps

### `memberships`

One finance profile per relevant user.

Suggested fields:
- `id`
- `user_id`
- `user_type_snapshot`: member, athlete
- `status`: active, expiring, expired, cancelled, paused, trial, comped
- `signup_source`: direct, referral, promo, admin-created, migrated/imported
- `starts_on`
- `expires_on`
- `notes`
- `referred_by_user_id`: nullable shortcut if useful, but detailed attribution lives in referral events
- timestamps

### `membership_package_subscriptions`

Join table because a membership can subscribe to one or more package objects.

Suggested fields:
- `id`
- `membership_id`
- `membership_package_id`
- `status`
- `starts_on`
- `ends_on`
- `package_code_snapshot`
- `package_family_snapshot`
- `billing_period_snapshot`
- `price_cents_snapshot`
- `params_snapshot`
- timestamps

The snapshots keep history stable when admins later edit package definitions.

### `membership_payments`

Append-only payment facts.

Suggested fields:
- `id`
- `membership_id`
- `membership_package_subscription_id`: nullable for general payments
- `amount_cents`
- `currency`
- `paid_on`
- `payment_method`: cash, bank_transfer, card_manual, other
- `payment_status`: paid, pending, refunded, failed, waived
- `notes`
- timestamps

### `promotion_campaigns`

Admin-managed campaigns.

Suggested fields:
- `id`
- `name`
- `description`
- `starts_on`
- `ends_on`
- `active`
- `params`
- timestamps

### `promotion_codes`

Concrete codes under campaigns.

Suggested fields:
- `id`
- `promotion_campaign_id`
- `code`
- `discount_type`: percent, fixed_amount, free_period, manual
- `discount_value`
- `max_redemptions`
- `active`
- timestamps

### `promotion_redemptions`

Links promotions to memberships, package subscriptions, and payments.

Suggested fields:
- `id`
- `promotion_campaign_id`
- `promotion_code_id`
- `membership_id`
- `membership_payment_id`
- `membership_package_subscription_id`
- `discount_type_snapshot`
- `discount_value_snapshot`
- `redeemed_at`

### `referral_programs`

Admin-managed incentive definitions.

Suggested fields:
- `id`
- `name`
- `description`
- `active`
- `reward_type`: credit, discount, free_period, manual
- `reward_value`
- `params`
- timestamps

### `referral_events`

Track the referral lifecycle.

Suggested fields:
- `id`
- `referral_program_id`
- `referrer_user_id`
- `referred_user_id`
- `membership_id`
- `status`: pending, approved, applied, rejected
- `signup_source_snapshot`
- `notes`
- timestamps

### `referral_rewards`

Track actual or pending incentives.

Suggested fields:
- `id`
- `referral_event_id`
- `recipient_user_id`
- `membership_id`
- `reward_type`
- `reward_value`
- `status`: pending, approved, applied, rejected
- `applied_at`
- timestamps

## Aggregates

Create `finance_aggregates` as a PostgreSQL materialized view.

It should support:
- Revenue by period.
- Active memberships.
- Expiring memberships.
- Package-level revenue and active counts.
- Package family performance.
- Payment status totals.
- Promo-attributed revenue and discounts.
- Referral-attributed signups and revenue.
- Pending referral rewards.
- Churn-risk buckets.
- Cohorts by start month.
- Member versus athlete revenue.

Refresh through an Oban job, similar to leaderboard refresh.

## Search Index Impact

Admin search should include denormalized finance facets:
- `membership_status`
- `user_type`
- `package_codes`
- `package_families`
- `package_tags`
- `promotion_campaign_ids`
- `referral_program_ids`
- `referrer_user_id`
- `expires_on`
- `expires_in_days`
- `last_payment_on`

Search is for lookup and filtering. Financial totals must come from Postgres
queries or materialized views.

## Technical Debt Anchor

Add this to `docs/technical_debt.md` when Phase 8 implementation starts:

`Membership packages currently store simple pricing, duration, tag, and metadata parameters. Future package rules may need complex entitlement logic, eligibility constraints, multi-service bundles, pause policies, location restrictions, and referral/promo interaction rules.`

## Open Implementation Decision

Referral rewards should be admin-reviewed/manual in v1.

Recommended status flow:
- `pending`
- `approved`
- `applied`
- `rejected`

Reason: this avoids accidental financial credits while referral and promotion
rules are still evolving.

