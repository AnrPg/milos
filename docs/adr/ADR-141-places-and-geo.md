# ADR-141: Places, location pins and geocoding
Date: 2026-10-19
Status: Accepted

## Context
Phase 2 opens the app beyond one gym: Γύρω μου, events, trials, check-in and
referral all need to know where a location is, what neighbourhood it is in and
when it is open. Owners must be able to pin a location without knowing its
coordinates (plan §5a, board 3).

## Decision
1. **PostGIS.** `facility_locations` gains `point geography(Point,4326)` with a
   GiST index, plus `neighbourhood`, `city`, `country_code`, `opening_hours`
   (weekly spans, several per day) and `accessibility`. Compose, CI and backups
   run `postgis/postgis`.
2. **Geocoding behind a port.** `Geocoder` (`search/2`, `reverse/3`) with a
   Photon adapter whose base URL comes from config (`PHOTON_BASE_URL`), so a
   self-hosted Photon replaces the public one without code changes. Admin
   endpoints `GET /api/org/:slug/admin/geocode`, `/geocode/reverse` and
   `/geocode/link`, rate limited to 30 a minute per user.
3. **Pins three ways** (board 3 Q2): address search, dragging or tapping the
   map, or pasting a Google Maps link. Short links are expanded server-side by
   `MapLinkResolver`, which follows at most four redirects and only to Google
   hosts (no SSRF), then reads `!3d!4d`, `@lat,lng` or a query parameter.
4. **Neighbourhood** is filled from reverse geocoding (district, then locality,
   then suburb) and stays editable; a typed value is never overwritten.
5. **Editor on its own page** (`/admin/settings/locations/:id`): name, address,
   neighbourhood, a full-width map, then a row per weekday for hours.

## Rationale
PostGIS gives distance ordering and radius queries in one indexed SQL query,
which every Phase 2 surface needs. Photon is open data (OSM), has no key and
can be self-hosted; the port keeps the vendor swappable.

## Alternatives Considered
- Haversine in plain Postgres: no index for radius queries at scale.
- Google Geocoding API: per-request cost and a key in config for a feature
  owners use a few times a year.

## Consequences
- Photon supports en, de, fr and it; other languages get its default names.
- Locations without a pin do not appear on maps; the settings list says so.

## Implementation Notes
- Migrations `20261018100000_places_geo`; code in
  `infrastructure/facility/photon_geocoder.ex`, `http_map_link_resolver.ex`,
  `facility/domain/map_link.ex`; web in `components/admin/location/`.
