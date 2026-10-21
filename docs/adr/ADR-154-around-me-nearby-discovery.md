# ADR-154: Γύρω μου: nearby discovery, home areas and saved-filter alerts
Date: 2026-10-20
Status: Accepted

## Context
Plan §5a board 9 (P2-M6) and vision §6–7.2 call for «Γύρω μου»: what is near a
signed-in person, by kind. That means upcoming open events, gyms with a
published page, open clubs and, when asked for, public posts. It has a map
mode, one filter shared with saved filters, and a daily alert for a saved
filter.

The pieces already exist, each in its own gym's tenant:
- events (ADR-153)
- public box profiles and their vocabularies (ADR-142)
- open clubs (ADR-143)
- trials (ADR-144)
- saved filters (ADR-151)
- PostGIS points on `facility_locations` (`palee_geo_point`, GiST)

Discovery has to read across gyms without loosening tenant RLS. It must never
show where a person is.

There was no neighbourhood vocabulary: `facility_locations.neighbourhood` is
free text.

## Decision
1. **A neighbourhood gazetteer.** `places_neighbourhoods` is public reference
   data: slug, kind (`neighbourhood` | `city`), Greek and English names,
   `city_slug`, a centroid, `radius_m` and an accent-free `search_key`. It has
   a GiST index and is seeded with 11 Greek cities and the neighbourhoods of
   Athens, Piraeus and Thessaloniki (86 rows). Later migrations add places by
   slug. `GET /api/places/neighbourhoods?q=` matches names regardless of case
   and accents, with prefix matches and cities first.
2. **«Η περιοχή μου» is private and server-side.** `user_home_areas` holds
   up to 5 neighbourhoods per person under owner RLS. Position 0 is the main
   one.
3. **Where a search starts.** The order of precedence is:
   1. the filter's own neighbourhoods
   2. the origin the request names: the saved area; a device point (rounded
      to 3 decimals, about 100 m, and never stored); a gazetteer place; or a
      typed place, tried in the gazetteer first and then through the
      `Geocoder` port, rounded the same way
   3. the saved area
   4. the person's box location

   With none of these the request gets `origin_required`. The pure
   `Places.Domain.Origin` makes the choice.
4. **One versioned filter.** `AroundFilter` (`v: 1`) is pure. It covers
   radius (0.5–50 km, default 3) or up to 5 neighbourhoods, kinds, the
   ADR-142 disciplines, audiences, amenities and languages, when, parts of
   the day, cost and a price cap. "When" is today, tomorrow, weekend, week or
   a range of at most 62 days.

   `WhenWindow` turns when and parts of the day into Europe/Athens wall-clock
   windows in UTC. DST is handled: a day can be 23 or 25 hours long; a time
   in the spring gap moves to the instant just after; an ambiguous autumn
   time takes its first occurrence.

   `to_params/1` is the canonical form. Saved filters for `around_me` store
   it, and so does the last-used filter, which a search remembers unless
   `remember: false`.
5. **Discovery through narrow definer functions, not a read model.**
   - **Matchers** are inlinable SQL with invoker rights:
     - `palee_around_host_places`
     - `palee_around_match_events` / `_boxes` / `_clubs` / `_posts`
     - `palee_around_tags_match`
   - **SECURITY DEFINER wrappers** call the matchers (ADR-131 §2 pattern):
     - `palee_around_events` / `_boxes` / `_clubs` / `_posts` for keyset
       pages with `count(*) OVER ()`
     - `palee_around_counts` for counts per radius, computed in one pass
     - `palee_around_pins` for the capped map list
     - `palee_around_alert_candidates`

   They return ids, distances and public card fields only. Cards are then
   read through the existing presenters, either in the person's session or
   in each gym's scope.

   Every spatial predicate gets both `ST_DWithin` and the geography `&&`
   against an enclosing envelope, so the GiST indexes are always usable.
   Every parameter is `p_`-prefixed, so no table column can shadow it.
6. **What shows, and where.**
   - Events: upcoming, `open_to_non_members`, not cancelled, soonest first.
     An event is placed at its own point, else its box location, else its
     box's nearest location.
   - Boxes: gyms with a published page, at their nearest pinned location.
     Gyms taking trials come first, then the nearest.
   - Clubs: open and not archived, joinable at once or on request, nearest
     first.
   - Posts: newest first, only when the `posts` kind is chosen. These are
     public club posts of published boxes, minus what the viewer reported.
     A person's public profile posts show only if they turned on «Φαίνομαι
     στο Γύρω μου» (`community_social_settings.visible_around`, off by
     default). They sit at the centroid of the person's main neighbourhood,
     never closer, and carry no tags, so any tag filter leaves them out.

   Tag filters apply through the host's published snapshot; an unpublished
   host matches none. Every row carries `distance_km` rounded to 0.1, and
   rows reuse the existing event, box, club and post card shapes.
7. **People who already have a gym** see other boxes in a collapsed
   placement (`placement: "collapsed"`). They never see their own gym, and
   never get boxes on the map or in alerts. The paid "shield" add-on is out
   of scope (see Consequences).
8. **Thin results.** When a search finds fewer than 5 items, `wider` adds
   per-kind counts at the next two rungs of 10 / 25 / 50 km.
9. **Map pins.** `POST /api/around/pins` takes a viewport whose diagonal is
   at most 60 km and returns at most 200 pins nearest the viewport's centre,
   plus `truncated`.
10. **Daily saved-filter alerts.** A named `around_me` filter can opt in
    (`saved_filters.alert_enabled`, `alert_checked_on`, `alert_checked_at`).
    `AroundAlertsJob` runs at 07:00 UTC. For each due filter it claims the
    Athens day (`alert_checked_on`) and counts only items created after
    `alert_checked_at`. When something is new it dispatches one
    `around_new_matches` notification, with dedupe key
    `around_new_matches:<filter>:<day>`, so a retry or a second sweep sends
    nothing more.

    The new notification type has push copy in all 12 locales
    (el: «Νέα γύρω σου» / «Νέα για «%{name}»: %{count}»).
11. **Privacy and limits.** Every route needs sign-in and a personal (user)
    context. Routes are rate-limited to 120 requests per minute in a
    dedicated `around` bucket. No response contains a person's position.

## Rationale
- Definer functions over a read-model table: there is nothing to keep in
  sync. Tenant RLS stays as it is, and each function's output is narrow
  and reviewable.
- Inlinable matchers shared by every wrapper keep the rules in one place
  (list, page, counts, pins, alert) while the planner still sees the
  spatial predicates.
- A seeded gazetteer gives stable ids for saved filters and home areas, and
  a precision floor for people's posts. Free-text neighbourhoods could do
  neither.

## Alternatives Considered
- **Denormalised `discovery_items` table fed by events.** Faster to query,
  but it duplicates publish, cancel and visibility state across five
  sources and needs backfills. Rejected for now. The function boundary lets
  us swap one in later.
- **An external gazetteer (OSM/Photon) at query time.** No stable ids, and
  an outside call on every request. Photon stays behind the `Geocoder` port
  for typed places only.
- **A person's posts at their box or a jittered point.** A box can identify
  a person, and jitter can be averaged away. A neighbourhood centroid
  cannot.

## Consequences
- The paid "shield" add-on (plan §5a, hiding other boxes completely for a
  member's gym) is not built: there is no billing add-on infrastructure yet.
  Only the collapsed placement exists.
- "When" narrows events only. Boxes, clubs and posts have no time of their
  own.
- The gazetteer covers 11 cities. Places elsewhere fall back to their city
  or to a geocoded point.
- The web client still has to build the screens (P2-M6 web half).

## Implementation Notes
- Hexagonal layout:
  - Domain, all pure: `Places.Domain.{AroundFilter, WhenWindow, Origin,
    SearchArea, AroundPlan, Cursor, SearchKey, AlertPolicy}`
  - Ports: `DiscoveryStore`, `GazetteerStore`, `HomeAreaStore`
  - Ecto adapters live under `Infrastructure.Places`
  - Use cases: `Application.{AroundMe, AroundArea, AroundAlerts}`
- Routes:
  - `POST /api/around/search`
  - `POST /api/around/search/:kind` (cursor pages)
  - `POST /api/around/pins`
  - `GET /api/places/neighbourhoods`
  - `GET|PUT /api/me/around/area`
  - `PUT /api/me/filters/:surface/:id/alert`
  - `PUT /api/me/social/around-visibility`
- `user_home_areas` is a personal table (`Tenancy.Audit` personal list). No
  new tenant table was added.
- New partial indexes:
  - `community_events_open_point_index`: GiST on open, uncancelled, pinned
    events
  - `community_events_open_location_index`
  - `community_posts_public_organization_index`
- EXPLAIN (ANALYZE) on 20,000 synthetic gyms and 200,000 events:
  - Events: own points use `community_events_open_point_index`. Box-placed
    events go through `facility_locations_point_index`, then
    `community_events_organization_id_starts_at_index`.
  - Boxes and clubs: `facility_locations_point_index`.
  - Posts: `community_posts_public_organization_index`, with
    `places_neighbourhoods_point_index` for people's posts.
  - Timings: 3 km events in about 9 ms; the full `palee_around_pins`
    definer in about 12 ms.
- The first integration run found that `organization_public_profiles` draft
  columns (`disciplines`, …) and `places_neighbourhoods.radius_m` were
  shadowing same-named function parameters. That is why every parameter is
  `p_`-prefixed and the adapter casts every placeholder.
