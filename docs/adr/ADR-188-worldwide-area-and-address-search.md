# ADR-188: Worldwide area and address search through a self-hostable OpenStreetMap geocoder
Date: 2026-10-23
Status: Accepted

## Context
«Πού προπονείσαι;» on /welcome, «Η περιοχή μου», the Around me "search elsewhere" sheet and the place
filter all searched only the curated gazetteer of ADR-154: a few Greek cities and their neighbourhoods,
seeded by a migration. Anyone outside it (or typing an address) found nothing. ANR wants any country,
city, neighbourhood or address, without paid external services, preferably in the cluster.

Options weighed:
- **Bundled data** (GeoNames, Who's On First) in Postgres: offline and simple, but no addresses and
  patchy neighbourhoods; hundreds of MB per refresh shipped through migrations.
- **Nominatim**: complete, but not built for as-you-type search (its public usage policy forbids
  autocomplete) and heavy to run (full Postgres import).
- **Pelias**: excellent, but Elasticsearch plus several importers and services to operate.
- **Photon** (komoot, OpenStreetMap): built for as-you-type search, typo tolerant, filterable by
  layer (city / district / locality / street / house), local + English/German/French/Italian names,
  prebuilt weekly indexes, one Java container. Already the admin geocoder (ADR-141), behind the
  `Geocoder` port and `PHOTON_BASE_URL`.

## Decision
- **Photon is the worldwide source**, self-hosted in the cluster (docs/operations/self-hosted-photon.md,
  ops/photon/photon.yaml); `PHOTON_BASE_URL` points at it. The public komoot instance remains the
  default only until that is deployed.
- **The gazetteer stays the single model of an area.** `places_neighbourhoods` gains `source`
  (`curated` | `osm`) and `context` / `context_en` (what tells namesakes apart: city, or region and
  country). Home areas, filters, saved searches and post centroids keep pointing at gazetteer ids, so
  nothing downstream changes.
- **Search** (`GET /places/neighbourhoods`): stored places first (curated and previously picked, a
  trigram index keeps the substring match fast); only when they are fewer than 6 and the query has 3+
  letters is Photon asked, twice in parallel (local names and English), with layer filters. Results
  become suggestions with a deterministic UUIDv5 id derived from the OSM object (`osm-r62428`), a
  radius from their bounding box (300 m–50 km, else by type), and a signed `ref` (24 h). Namesakes within
  5 km of a stored place are dropped. `remote` says `ok`, `unavailable` or `skipped`; a Photon outage only
  hides worldwide suggestions, stored places still answer.
- **Picking** (`POST /places/neighbourhoods/import {ref}`): the server verifies its own signature and
  upserts the row (refreshing names and shape on repeat). Only signed results reach the table; RLS lets
  sessions insert/update `osm` rows only, curated rows stay migration-only.
- **Addresses never become areas.** An address suggestion resolves, at pick time, to the nearest
  district/locality/city Photon knows that plausibly covers it; failing that (or with Photon down) to a
  ~1 km grid cell (`geo-<lat>-<lng>`, 2 decimals) named after its neighbourhood or city. The address
  itself is not stored, matching ADR-154's privacy rule that a main neighbourhood's centroid may be
  shown publicly.
- The web client resolves suggestions through one hook (`useResolvePlace`) in the area picker, the
  "search elsewhere" sheet and the place filter, and shows each row's context and kind.

## Consequences
- Coverage is the world's OpenStreetMap data; quality of neighbourhood names varies by country.
- A planet Photon needs ~100 GB of disk and generous memory (see the ops guide); a continent index is a
  cheaper start. Until it is deployed, searches go to photon.komoot.io under its fair-use terms.
- Imported rows accumulate slowly (only picked places); they are reference data and can be refreshed.
- Follow-ups: a server-side cache of Photon answers if traffic grows; pruning `osm` rows nobody uses.
