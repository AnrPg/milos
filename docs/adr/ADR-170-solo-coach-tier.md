# ADR-170: Solo-coach tier, platform plans and the coach-centred Box
Date: 2026-10-21
Status: Accepted

## Context
Vision §7.10 and Phase 3 milestone P3-M8 add the independent personal coach: someone
with no gym, a handful of clients, sessions in a park or on a call, a session package
instead of a membership, and a small «Team» club for their people. Organizations
already carry a `provider_kind` (gym | coach, ADR-162) that the provider switch uses,
but nothing could create a coach organization self-serve, nothing described what a
customer of Milos pays for, and Box spoke only in gym words.

The tier prices are not decided (plan §7 Q1). Whatever we build must let the platform
team set and change prices, limits and trials without a deploy, must never show a
price that is still a guess, and must not lock anyone out while billing does not
exist yet.

## Decision
1. **Plans are platform data, not code.** `platform_plans` (code, audience gym|coach,
   name, `limits` jsonb, monthly and annual price in cents, currency, `price_status`
   placeholder|confirmed, `trial_days`, `is_default` per audience, public, active,
   position) is readable by everyone and writable only by vendors.
   `organization_platform_subscriptions` holds one row per organization: plan code,
   status (trialing | active | past_due | cancelled | comped), trial end, an optional
   price override and notes; owners and admins read their own, vendors write. Both
   tables are in `Tenancy.Audit`'s platform-administered list and the tenant-data
   policy. Seeded defaults: `solo_coach` (2 staff seats, 50 active clients, €19 / €190,
   30-day trial, **placeholder**) and `gym` (no limits, no price, placeholder).
2. **Every organization gets a subscription at creation.** `TenantDefaults` calls
   `PlatformPlans.ensure_subscription/1` inside the creation transaction (ADR-133); a
   SECURITY DEFINER function inserts the default plan for the organization's kind,
   trialing when the plan has trial days. Existing organizations were backfilled as
   active on their kind's default plan.
3. **Limits are a small, explicit vocabulary.** `PlanLimits` knows `staff_seats` (hard:
   issuing a staff invitation or granting a staff role beyond it answers 409
   `plan_limit_reached`) and `active_clients` (soft: shown, never enforced). Pending
   staff invitations count as seats. A missing limit means unlimited. New keys are
   added to the module, never as free strings.
4. **Status never locks anyone out.** `SubscriptionPolicy` derives `trial_expired`
   and a notice (trial ending within 7 days, trial over, payment due, cancelled) that
   the admin console shows as one line. Nothing is switched off; billing enforcement
   is a later, separate decision.
5. **Placeholder prices are never shown to customers.** The web shows a price only
   when `price_status` is `confirmed` (or an override exists for that organization);
   otherwise «pricing to be announced». The platform console (`/platform/plans`)
   edits plans and assigns plans per organization.
6. **Self-serve coach practice.** `POST /api/coach-practices` (any signed-in account,
   one practice per account) creates a `provider_kind: coach` organization with a free
   slug (Greek and Cyrillic transliterated), the caller as owner + coach, tenant
   defaults, the solo-coach trial, and names the organization's gym club
   «Team <first name>» (ADR-138) unless given another name.
7. **Coach onboarding is the same checklist with another step list.** The onboarding
   checklist takes an audience: gym keeps its six steps; coach gets profile, sessions,
   packages, team, bootcamp, invite, tour, each completed from real signals (published
   public page, appointment slots, packages, an open event, an invitation).
8. **Coach-centred Box is a layout, not a second app.** Box picks a layout from the
   selected provider's kind: the coach layout titles itself «Name · Personal coach»,
   replaces the next class with the next session (with the call link for online
   sessions), shows Sessions · Videos · Nutrition · Messages by entitlement and the
   session package's remaining sessions. Session packages are the existing finance
   plans with a `pt_sessions` allowance; open bootcamps are open community events.
   `BOX_EXTENSIONS` is a typed registry other features (PT squads, P3-M6) plug into
   per provider kind.
9. **Online sessions.** Appointment slots gain `mode` (in_person | online) and an
   https `meeting_url`; the link is returned only to the client who booked the slot
   and to staff.

## Consequences
- Prices, limits and trials change from the platform console without a deploy; the
  first confirmed price appears to customers the moment it is confirmed.
- The only hard enforcement is staff seats. Client counts and statuses are visible
  but advisory until billing exists.
- A gym can later get tiered plans by adding `gym` audience rows; nothing in the code
  assumes one plan per audience except the single default.
- Box stays one component tree; new provider kinds add a layout and extensions.
