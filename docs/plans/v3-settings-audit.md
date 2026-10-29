# V3-M11 · Settings audit (CP-H1)

> Date: 29 October 2026 · Milestone V3-M11 «Συνταγές στησίματος και απλοποίηση ρυθμίσεων» · ADR-255
> Why: the competitor review found that Palee feels cluttered (≈104 switches over 142 staff pages).
> Kilo, Arbox and PushPress win on «easy to set up». The owner wants a calm settings screen
> without option overload. Principles: §4 of the product vision (one home per object, stable
> screens, a card with nothing in it is hidden), names from `docs/product/ontology.md`.

## How to read this

Every business setting the API exposes is listed once, with:

- **Where**: table / storage and the endpoint that changes it.
- **Default**: what a new business gets.
- **Who needs it**: the person who would ever change it, and how often.
- **Verdict**:
  - **Basic**: stays on the main settings screen.
  - **Advanced**: moves under «Προχωρημένα» (hidden until opened). The default is right for most boxes.
  - **Derive**: the app works it out (from the time zone, the country, the box type the owner picked in
    a setup recipe, …). It may stay editable under «Προχωρημένα», but nobody should have to set it.
  - **Remove (UI)**: no owner should see it. The column stays in code; only the screen loses it.

No setting is deleted in code. The verdicts live in one place in code,
`Palee.Setup.Domain.SettingsCatalog`, and reach the web through
`GET /api/org/:slug/admin/setup/settings` (one row per setting with `advanced: true|false` and the
verdict) and the `advanced_settings` list in `GET /api/org/:slug/admin/settings`. The web hides every
advanced setting by default and shows them under «Προχωρημένα».

The setup recipes (CP-H2, same ADR) set most of the «Derive» rows in one step when a box starts.

## Summary

| Verdict | Count | What it means for the screen |
|---|---|---|
| Basic | 17 | The main settings screen |
| Advanced | 36 | One «Προχωρημένα» section per area, closed by default |
| Derive | 10 | Set by the app or by a setup recipe |
| Remove (UI) | 4 | Hidden from owners; kept for the Palee team or internal use |
| **Total business settings** | **67** | including the 5 class-type fields (§J); plus ≈50 per-package fields (§K) |

The counts are checked by `test/palee/setup/domain/settings_catalog_test.exs` against the catalog in
code, so this table and the code cannot drift apart.

Personal settings (Εγώ › Ρυθμίσεις) are listed in §P for completeness; they are not part of the
business settings screen and keep their own home.

## A. Business: organization settings

Table `organization_settings` (columns, and the `settings` JSON map for keys below).

| Key (catalog) | Where | Default | Who needs it | Verdict |
|---|---|---|---|---|
| `organization.timezone` | `organization_settings.timezone`; `PUT /admin/settings/time-zone` | inferred from the first staff device (ADR-176) | Owner, once, to confirm | **Derive** (confirm once on the first-run checklist) |
| `organization.default_locale` | `organization_settings.default_locale`; Palee team | `en` | Nobody after sign-up | **Derive** (from the business country, fiscal identity) |
| `organization.invitation_lifetime_seconds` | `organization_settings`; Palee team | 7 days | Palee team | **Remove (UI)** |
| `branding.brand_name` | `organization_settings.brand_name`; `/admin/branding` | business name | Owner, once | **Basic** |
| `branding.logo` | `brand_logo_object_key`; logo upload (ADR-121) | none | Owner, once | **Basic** |
| `branding.primary_color` | `brand_primary_color` | Palee palette | Owner, rarely | **Derive** (from the logo, `BrandPalette`), editable in «Προχωρημένα» |
| `provider.kind` | `organizations.provider_kind`; `PATCH /admin/settings` `provider` (ADR-162) | `gym` | Owner, once | **Derive** (from the setup recipe; «Ανεξάρτητος coach» sets `coach`) |
| `access.role_grants` | `settings["role_grants"]`; `PUT /admin/role-access/:role` | none (role defaults, ADR-099) | Owner of a box with front desk staff | **Advanced** |
| `join_link.member` | `settings["join_link"]`; `PUT /api/org/:slug/join-link` (ADR-216) | off | Owner, once | **Basic** |
| `join_link.athlete` | `settings["join_link"]` | off | Coach with remote athletes | **Advanced** |
| `workouts.wod_goals_visible_by_default` | `settings["workouts"]`; `PATCH /admin/settings` (ADR-163) | off | Head coach | **Advanced** |
| `workouts.wod_assistant_enabled` | `settings["workouts"]` (ADR-180) | on | Head coach | **Advanced** |
| `onboarding.checklist` | `settings["onboarding"]` (ADR-107/183) | open | — (progress, not a choice) | **Derive** |

## B. Business: money (finance settings)

Table `finance_settings`; `PATCH /admin/settings` section `finance`.

| Key | Default | Who needs it | Verdict |
|---|---|---|---|
| `finance.document_mode` | `invoice` | — | **Derive** (from the country profile, ADR-240; Greece issues receipts for B2C) |
| `finance.package_modules` | `group_classes`, `online_coaching` | Owner, once | **Derive** (from the setup recipe: open gym, personal training, …), editable in «Προχωρημένα» |
| `finance.subscription_grace_days` | 3 | Owner, rarely | **Advanced** |
| `finance.subscription_expiry_reminder_days` | 5 | Owner, rarely | **Advanced** |
| `finance.payment_reminder_interval_days` | 7 | Owner, rarely | **Advanced** |
| `finance.entitlement_enforcement_mode` | `observe` | Palee team during roll-out | **Remove (UI)** (not in the API; internal) |
| `finance.entitlement_timezone` | `Europe/Athens` | — | **Derive** (the box's time zone, ADR-179) |

## C. Business: class booking rules (scheduling settings)

Table `scheduling_settings`; `PATCH /admin/settings` section `scheduling`. Names from ontology §4.6a.

| Key | Default | Who needs it | Verdict |
|---|---|---|---|
| `scheduling.default_capacity` | 12 | Owner, once | **Basic** |
| `scheduling.default_auto_approve` («Αυτόματη επιβεβαίωση κρατήσεων») | off | Owner, once | **Basic** (the recipes turn it on for CrossFit and open gyms) |
| `scheduling.default_cancellation_cutoff_minutes` («Καθυστερημένη ακύρωση») | none | Owner, once | **Basic** |
| `scheduling.default_booking_window_days` («Άνοιγμα κρατήσεων») | none (any time) | Owner, rarely | **Advanced** |
| `scheduling.default_booking_timeout_minutes` («Χρόνος για απάντηση σε αίτηση κράτησης») | 60 | Only without automatic confirmation | **Advanced** (and hidden while automatic confirmation is on) |

## D. Business: streaks and leaderboard (gamification settings)

Table `gamification_settings`; `PATCH /admin/settings` section `gamification` (ADR-229).

| Key | Default | Who needs it | Verdict |
|---|---|---|---|
| `gamification.leaderboard_enabled` | on | Owner, once | **Basic** |
| `gamification.streak_shields` («Ασπίδα σερί») | 1 | Owner, rarely | **Advanced** |
| `gamification.streak_shield_reset_day` («Ανανέωση ασπίδων») | each client's sign-up day | Owner, rarely | **Advanced** |

## E. Business: check-in

Table `facility_check_in_settings`; `PUT /admin/check-in/settings` (ADR-155, ADR-173).

| Key | Default | Who needs it | Verdict |
|---|---|---|---|
| `check_in.window_before_minutes` | 30 | Owner, rarely | **Advanced** |
| `check_in.window_after_minutes` | 15 | Owner, rarely | **Advanced** |
| `check_in.open_gym_requires_package` | on | Box with open gym | **Derive** (from the recipe), editable in «Προχωρημένα» |
| `check_in.visitor_trial_offer` | on | — | **Advanced** (follows whether trials are on) |
| `check_in.desk_override` | off | Box with front desk | **Advanced** |
| `check_in.door_rotation_seconds` | 30 | — | **Remove (UI)** (security default) |
| `check_in.member_code_mode` | `rotating` | Box with a door scanner | **Advanced** |
| `check_in.geofence_reminder` | on | Owner, rarely | **Advanced** |

## F. Business: community

Table `community_settings`; `PUT /admin/community/settings` (ADR-143, ADR-169).

| Key | Default | Who needs it | Verdict |
|---|---|---|---|
| `community.member_groups` | `approval` | Owner, rarely | **Advanced** |
| `community.partners_enabled` | on | Owner, rarely | **Advanced** |

## G. Business: trial visitors («Δοκιμαστικό»)

Table `scheduling_trial_policies`; `PUT /admin/trial-policy`.

| Key | Default | Who needs it | Verdict |
|---|---|---|---|
| `trials.enabled` | off | Owner, once | **Basic** (the recipes turn it on) |
| `trials.seats_per_class` | 2 | Owner, once | **Basic** |
| `trials.bring_note` | none | Owner, once | **Basic** |
| `trials.approval` | `auto` | Owner, rarely | **Advanced** |
| `trials.weekly_limit` | none | Owner, rarely | **Advanced** |
| `trials.per_person_limit` | 1 | — | **Advanced** |
| `trials.class_type_ids` | all | Owner, rarely | **Advanced** |
| `trials.horizon_days` | none | — | **Advanced** |
| `trials.first_timers_only` | off | — | **Advanced** |
| `trials.no_show_consumes` | off | — | **Advanced** |
| `trials.conversion_package_id` | none | Owner, once | **Derive** (the recipe's first membership), editable in «Προχωρημένα» |

## H. Business: AI

Table `organization_ai_settings`; `PUT /admin/ai-settings` (ADR-174).

| Key | Default | Who needs it | Verdict |
|---|---|---|---|
| `ai.api_key` | none (Palee's key) | Owner who brings their own key | **Advanced** |
| `ai.model` | Palee's choice | — | **Remove (UI)** (the Palee team picks the model) |
| `ai.scaling_enabled` | off | Head coach | **Advanced** |
| `ai.voice_enabled` | off | Head coach | **Advanced** |

## I. Business: «Φέρε φίλο» (referral programme)

Table `referral_programs` (ADR-156).

| Key | Default | Who needs it | Verdict |
|---|---|---|---|
| `referrals.active` | on once created | Owner, once | **Basic** |
| `referrals.reward` (`reward_type`, `reward_value`, `reward_note`) | manual, 0 | Owner, once | **Basic** |
| `referrals.friend_reward` (`friend_reward_type`, `_value`, `_note`) | none | Owner, once | **Basic** |
| `referrals.qualifying_stage` | `paid` | — | **Advanced** |
| `referrals.attribution_days` | 30 | — | **Advanced** |
| `referrals.yearly_cap` | none | Owner, rarely | **Advanced** |
| `referrals.approval` | `manual` | Owner, rarely | **Advanced** |

## J. Per class type (Τύπος τμήματος)

`/admin/class-types` (ADR-097). Not switches, but every class type form shows them.

| Field | Default | Verdict |
|---|---|---|
| name | — | **Basic** |
| kind (class / event) | class | **Basic** |
| level | all levels | **Advanced** |
| audiences | open to everyone | **Advanced** |
| credit_cost | 1 | **Advanced** |

## K. Per subscription package (Πακέτο συνδρομής)

`/admin/finance/packages` with the field catalog `Finance.Domain.PackageCatalog` (≈50 fields across
`terms`, `group_classes`, `booking`, `personal_training`, `online_coaching`, `content`, `facility`).
These already open by section in the package form.

- **Basic:** name, package type, price, billing period, visits (`group_classes.visits`), validity
  (`terms.validity`), automatic renewal (`terms.auto_renew`), sold online (ADR-248).
- **Advanced:** everything else (stacking, once per person, new members only, minimum commitment,
  joining fee, validity start, expiry reminder override, beneficiaries, seats, class type limits,
  rollover, time windows, the three per-package booking overrides, every personal-training and
  online-programming detail, facility access and amenities).
- **Derive:** the package modules a box offers (§B) decide which sections the form shows at all.

## L. Business: legal identity, payments (V3-M1, V3-M4)

These are required facts, not choices: the legal name, tax id, tax office, address and the payment
provider account. They stay **Basic** on their own screens («Στοιχεία επιχείρησης», «Πληρωμές»).
The tax authority connection (environment, credentials) is **Advanced**. Out of scope for the recipes.

## M. Platform (Palee team only)

Web Push keys (`/platform/push-settings`, ADR-218), plans, activation links: not business settings,
never shown to owners. Not counted above.

## P. Personal settings (for completeness)

Each person's own choices, in Εγώ › Ρυθμίσεις, one home each (§4.1 of the vision). Not part of the
business screen; no change proposed here except that the defaults already follow «private by default»
(§4.5).

| Area | Settings | Where |
|---|---|---|
| Notifications | one switch per category × channel (ADR-199) | `/notifications/preferences` |
| Social | share bookings, hide from members, visible in Γύρω μου, private account, searchable | `/me/social/*` |
| Body | units, weight display, journal sections, measure reminder, default visibility, blur photos, compare mode, «πώς ένιωσες» prompt | `/me/body/settings` |
| Buddies | quiet hours, time zone, share phone | `/me/buddies/settings` |
| Partners | training-partner profile and discovery | `/me/partners/settings` |
| Wellness | check-in prompts | `/me/wellness/preferences` |
| Goals | weekly goal (ADR-229) | `/gamification/preferences` |

## What changes now, and what waits

- **Now (V3-M11, backend):** the catalog with a level per setting, the `advanced_settings` list on the
  settings response, the settings catalog endpoint, and the setup recipes that fill the «Derive» rows.
- **Waits for approved mockups:** the settings screen itself (one card per area, «Προχωρημένα» closed
  by default, a card with nothing basic in it hidden), and the first-run «Τι box είσαι;» step.
- **Open for ANR:** whether «Remove (UI)» rows should also be dropped from the API responses in v3.1
  (today they only disappear from screens), and whether `subscription_grace_days` should be basic.
