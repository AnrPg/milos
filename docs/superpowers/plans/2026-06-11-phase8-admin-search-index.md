# Phase 8 Admin Search and Indexing
Date: 2026-06-11
Status: Planning anchor

## Purpose

This note captures the intended shape of enriched admin search. The endpoint
started as `GET /api/admin/search?q=&role=member|athlete|all`, but Phase 8
planning expanded it to include finance, progress, injury, and satisfaction
facets.

## Contract Direction

Initial endpoint:

`GET /api/admin/search?q=&user_type=&role=&membership_status=&package_code=&package_tag=&promotion_campaign_id=&referral_program_id=&expires_within_days=&limit=`

Likely future filters:
- `workout_type`
- `scale_level`
- `completion_rate_bucket`
- `last_active_bucket`
- `class_time_bucket`
- `coach_assigned`
- `injury_status`
- `satisfaction_bucket`
- `communication_status`

## Meilisearch Document Shape

Suggested denormalized user document:

```json
{
  "id": "uuid",
  "nickname": "string",
  "role": "member | athlete | admin",
  "user_type": "member | athlete",
  "membership_status": "active | expiring | expired | cancelled | paused | trial | comped | null",
  "package_codes": ["monthly_unlimited"],
  "package_tags": ["crossfit", "remote"],
  "package_family": "unlimited | limited-visits | personal-programming | hybrid | null",
  "billing_periods": ["monthly"],
  "promotion_campaign_ids": ["uuid"],
  "referral_program_ids": ["uuid"],
  "referrer_user_id": "uuid | null",
  "expires_on": "date | null",
  "expires_in_days": 12,
  "last_payment_on": "date | null",
  "last_active_at": "datetime | null",
  "last_active_bucket": "active | cooling | inactive | dormant",
  "completion_rate_bucket": "high | medium | low | none",
  "injury_status": "none | active | recently_healed | recurring",
  "satisfaction_bucket": "high | neutral | low | unknown",
  "communication_status": "clear | unread | unresolved | needs_follow_up"
}
```

## Responsibility Split

Search is for fast lookup and drill-down, not financial truth.

- `GET /api/admin/search` uses Meilisearch for fuzzy user lookup and filterable facets.
- `GET /api/admin/finance/summary` reads Finance queries or `finance_aggregates`.
- `GET /api/admin/finance/members/:id` reads authoritative Finance tables.
- `GET /api/admin/coaching/summary` reads `coaching_aggregates`.
- Review, injury, and communication pages read their owning contexts.

## Index Refresh Events

Refresh or enqueue reindex after:
- User created.
- User role changed.
- Membership created or status changed.
- Package subscription added/removed/changed.
- Payment recorded or refunded.
- Promo redemption recorded.
- Referral status changed.
- Workout/class activity changes derived engagement buckets.
- Injury reported/healed.
- Review submitted or triaged.
- Communication thread status changed.

## Implementation Notes

Add:
- `MilosTraining.Infrastructure.Search.MemberIndexer`.
- `MilosTraining.Workers.IndexUserJob`.
- Public application service for admin search.
- Admin controller endpoint.
- Tests proving filter translation and role/user-type scoping.

Meilisearch should store denormalized filter fields only. It should not be used
as the source for revenue totals, churn totals, satisfaction totals, or referral
reward accounting.

