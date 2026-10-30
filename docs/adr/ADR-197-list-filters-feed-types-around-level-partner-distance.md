# ADR-197: One filter pattern on every list; feed types, Around level, partner disciplines and distance
Date: 2026-10-24
Status: Accepted; the partner distance «only in open clubs» is superseded by ADR-280 (2026-10-30): distance now applies to the one public deck, still from neighbourhood centroids in fixed steps.

## Context
Vision §7.2 and §8.5 ask for the chip row + «Φίλτρα (n)» sheet on every list, with the filter remembered (ADR-151). Some lists had none (Feed, club Ροή, Find, events, appointments, workouts, reviews). Some had their own controls: tag buttons on videos, an «all channels» header button on the club, a toggled panel on the Partners deck. Three filters in the vision table had no data behind them: the feed's type and coaches-only filters, the Γύρω μου level filter, and the Partners discipline and distance filters.

## Decision
- **One component.** `ListFilters` takes a declared shape (`one` / `many` / `toggle` per field) and draws the chip row (`fit`, never scrolling sideways) and the sheet. `useListFilter(surface, shape, within?)` remembers the filter. `within` stores one entry inside a surface: the club Ροή by club id, the Feed's posts under `posts`, the Partners deck by club id. A field with fewer than two choices is hidden, and so is the whole row when no field is left, so no list ever shows an empty filter.
- **Server-side where paging needs it.** `GET /me/community/feed` takes `types[]` (`announcement` = posts in the club's announcement channels, `pr`, `event`) and `coaches_only` (posts by the box's staff). A narrowed feed shows club posts only. Lists that load whole are filtered on the client. Their options come from the loaded values only.
- **New surfaces** in `FilterPolicy`: `box_workouts`, `box_videos`, `box_appointments`, `events`, `find_clubs`, `my_posts`, `reviews`.
- **Γύρω μου level** (`levels`: `beginner`, `all_levels`, `advanced`, the class_types levels) keeps hosts that run a non-archived class type at one of the chosen levels. Posts have no level, so a level filter hides posts. It counts as one facet in «Φίλτρα (n)».
- **Partner disciplines.** A partner profile holds up to 5 disciplines from the box-profile vocabulary. They show on the card, count in «what you share» and in the score, and the deck can filter by one. Interests still only *suggest* (ADR-183): the picker offers your interests first, but the filter reads the partner profile.
- **Partner distance.** ADR-169 refused distance. This ADR allows it with three limits: only in **open clubs**, only between people who already show in Γύρω μου (`visible_around`) and have a main neighbourhood, and measured from neighbourhood centroids, never from a live location. The deck offers fixed steps (2/5/10/25 km), never a number of km. The overview says `distance: available | needs_area | null`, so the deck explains what is missing instead of offering a filter that would come back empty. The SQL function `palee_partner_people_within` (SECURITY DEFINER) takes the viewer from `app.user_id` and returns ids only.

## Rationale
One declared shape keeps the stored params, the chips and the sheet in step, and an unknown or broken stored value falls back to «nothing picked». Measuring between neighbourhoods that people already show in Γύρω μου adds nothing that Γύρω μου does not already reveal, and keeping it to open clubs leaves a box's private member list out of it.

## Alternatives Considered
- Exact distance from the last known location: this would reveal where someone is, so it was rejected.
- Filtering partners by interests: this goes against ADR-183.
- One saved-filter surface per club: this would grow the surface allowlist without limit, so the `within` entries are used instead.

## Consequences
- Each new list declares a shape and a surface, and nothing else.
- Remembered params are capped at 4096 bytes per surface, so the club Ροή entries share that space. Old entries can be dropped by a later client.
- The level filter needs class types. A host that has none never matches a level filter.

## Implementation Notes
Migrations `20261218100000_around_level` (adds `p_levels` to every `palee_around_*` function) and `20261218200000_partner_disciplines_and_distance`. The appointments filter reads the slot's kind or, for a booking without a slot, the booking's allowance.
