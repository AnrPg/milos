# Milos redesign: handoff report (2026-10-19)

> For the next agent continuing the redesign. Read this file first, then the documents it
> points to. It covers the big picture, where things stand, every decision taken so far, the
> final mockups, how the owner wants to work, and exactly what to do next.
>
> State at writing: Phase 1 is merged. **Phase 2 M1 is merged** into `redesign/social-centered`
> (PR #9, merge `67869ea2`). **Phase 2 M2 is next.**

---

## 0. Read order

1. This file.
2. `docs/product/2026-10-15-milos-product-vision-and-ia.md`: **the brief**. It is the product source of
   truth, and its §4 principles are non-negotiable.
3. `docs/product/mockups/milos-ia-mockup.html`: **the final clickable design** (34 phone screens).
   Open it in a browser. PNGs are in `docs/product/mockups/screens/`.
4. `docs/plans/redesign-phase-2-open-up.md`: **the Phase 2 plan**. It has the decisions (§3),
   architecture (§4), milestones (§5), the screen-level UX decisions (§5a) and progress (§9).
5. `docs/plans/redesign-phase-1-member-app.md`: what Phase 1 built (shell, hubs, community,
   visibility ladder, journal text).
6. ADRs `docs/adr/ADR-137` … `ADR-142`, `ADR-148`, `ADR-151` (see §6).
7. `.claude/CLAUDE.md` (multi-agent rules) and `AGENTS.md` / `apps/api/AGENTS.md` (hexagonal rules).

Ignore as a spec: `docs/product/mockups/milos-bottom-bar-exploration.html`. It is **superseded**
and records only why 13 rejected options were rejected.

---

## 1. The big picture

### What Milos is
Milos is **gym-management software that turns the gym into a living club**. The product is
B2B2C:

1. A **gym owner** (or an independent coach) pays for the SaaS. They run bookings, packages,
   finance and coaching.
2. Their **members must install the app** to book and pay, which gives distribution with no paid
   user acquisition.
3. Inside the app, the **journal** gives single-player value, and the gym's **club** gives social
   value with **no cold start**, because the members already know each other.
4. Then the platform **opens outward under the owner's control**: open clubs, events, trials,
   `Γύρω μου` (nearby). New clients come in through the front door on the owner's terms.
   There is no discount marketplace. That is the anti-ClassPass pitch.

The primary market is **Greece**. UI copy is Greek-first, and the app ships in 12 locales.

### The member app: 4 fixed tabs
`Αρχική` (Feed, landing) · `Box` · `Ημερολόγιο` (Journal) · `Εγώ` (Me). Every object has
**exactly one home tab** (brief §6.3).

### Non-negotiable principles (brief §4, condensed)
1. Every object has one home; elsewhere it appears only as a card linking home.
2. **Stable, predictable screens.** Layout and card order never change. Empty states keep their
   slot. No adaptive "Today" screens.
3. `⊕` means "post for others" and exists only top-left in the Feed. Writing for yourself is
   always a labelled button (`Νέα καταχώρηση`, `Καταγραφή`, `Έναρξη`). No unlabelled `+`
   anywhere else.
4. Comparison with others lives in clubs and is opt-in. Comparison with yourself lives in the
   Journal.
5. **Private by default.** Injuries are the exception: coaches always see them.
6. **Club ≠ Box.** The club is the social space; the Box is the service relationship.
7. Swipe only for people, and only with mutual consent (Phase 3).
8. No "More" drawer. Secondary things live in `Εγώ`.
9. The journal belongs to the athlete, not the gym, and follows them across gyms.
10. Do no harm with body and food data (brief §8.6; plan §6 checklist).

### Phases (the brief's v1/v2/v3 = Phase 1/2/3; release tags are different)
| Phase | Pitch | Status |
|---|---|---|
| Phase 1: re-architecture and the gym as a club | «Τα μέλη σου μένουν γιατί είναι κοινότητα.» | **Done** (PRs #6, #7) |
| Phase 2: open up, under the owner's control | «Φέρνεις νέους πελάτες με τους δικούς σου όρους.» | **M1 of 14 done** (PR #9) |
| Phase 3: depth and a second market | «Πουλάς προγράμματα, όχι μόνο συνδρομές.» | Not started; do not build, do not block |

Release tags: the pre-redesign product is `v1.0.0`. The redesign ships as **`v2.0.0`**.

---

## 2. Repository, branches, process

- Repo: `github.com/AnrPg/milos`. Web is a Next.js 16 PWA in `apps/web`. The API is
  Elixir/Phoenix in `apps/api`, hexagonal with bounded contexts.
- **Integration branch: `redesign/social-centered`.** Each milestone is one PR into it from a
  short-lived branch. Cloud sessions are pinned to their own session branch. Small docs-only
  changes may go straight to the integration branch.
- **GitHub is the only shared state between agents.** Never rely on uncommitted files. The
  project folder `/mnt/project-files` is shared only by Claude sessions in this project; other
  agents don't see it, so anything that matters goes in the repo.
- **GitHub CI has no runners.** Jobs stay queued or fail. Never wait on CI and never treat its
  red as a real failure. **The local gate is the gate** (see §8), and the PR body reports its
  results.
- PRs: the owner (GitHub `AnrPg`) is the author of PRs opened from these sessions, so GitHub
  refuses to request his review. Assign him instead. He merges himself.
- Open PRs you may meet:
  - **#8** (draft, branch `claude/project-thread-2aeoqr`): Gemini cost metering. **ADR number
    clash:** it adds `docs/adr/ADR-141-ai-usage-metering.md`, but ADR-141 is now
    *Places and geo* (merged). The Phase 2 plan reserves ADR-141…151, so #8 must be renumbered
    to **ADR-152** (file name, README row, and references in its code comments) before it
    merges. Tell the owner if that thread doesn't do it.
- Other branches `main` and `redesign/journal-centric-app` are not part of this work.

---

## 3. How the owner works (Apostolos)

These preferences are firm. Several are also saved in the project memory.

1. **Most robust, future-proof solution, never the easiest.** The app isn't released, so
   refactors are free. **No per-gym rollout flags.**
2. **Design the ideal first, then build what's missing.** Never sidestep a feature or settle for a
   weaker approach because backend, tables or components "don't exist yet". Build them.
3. **UX is decided per screen, interactively, on visual boards.** The mockup gives direction,
   not a pixel spec. Before building any screen:
   1. Build the backend (data, API, OpenAPI) first.
   2. Publish a **UX board**: an Artifact page with phone mockups per alternative, radio picks,
      multi-pick lists, a notes box per question, and «✎ Write on it» comment pins. Mark your
      recommended pick.
   3. He fills it in and says "done". Read the answers (Artifact db collection `answers`, via the
      ArtifactData tool) and the comment threads (ArtifactComments). Reply to each comment and
      resolve it.
   4. Record every decision in plan §5a, then build the web side from §5a.
   Board recipe that works: capabilities `{db:{}, user:{}, comments:{composer_only:true}}`,
   connect the db **before** anything else with a ~12 s timeout, and keep a local copy of picks
   plus a «Copy my answers» fallback. Avoid global names that clash with browser built-ins (one
   board crashed on that). Text answers he types into a note field **are** answers. Never treat a
   question as blank without reading the notes.
4. **He reads mockups better than text.** Give alternatives and pick lists, not prose questions.
5. **Tests cadence:** compile, typecheck, format and lint per slice. Run the full API and web suites
   **once at the end of a milestone**, not after every subtask. The full API suite takes ~4–5 minutes.
6. **Don't lecture about security. Get the job done with the fewest asks.**
7. Reply in English unless he writes Greek. Short, plain answers.
8. Commits must not contain model names. Use the attribution trailers the session gives you.

---

## 4. What exists after Phase 1 (short)

See the Phase 1 plan §9 and ADR-137…140 for detail.
- **Shell (ADR-137):** a 4-tab bottom bar. Member pages moved under `/box/*`, `/journal/*` and
  `/me/*`, with old URLs redirecting. Execution and class-timer routes are full-screen and
  unchanged.
- **Community (ADR-138):** context `Community` with `community_clubs` (kinds
  `gym|open|member_group|pt_squad|season`; only `gym` used so far), channels (`announcements`,
  `wod`, `challenges`, `class_slot`, `season`, `custom`), memberships, posts (audience column;
  only `club_channel` used), reactions and comments. There is one closed club per gym, and the
  feed has a club bar, origin labels, `⊕` compose and an optional workout attachment. The
  `#wod-σήμερα` card has an opt-in leaderboard. `#challenges` auto-joins, and class-slot groups
  form from ≥3 bookings in 28 days. Box announcements read `#ανακοινώσεις`.
- **Journal (ADR-139/140):** a visibility ladder (`private | coach_can_view |
  coach_reply_requested | rated | posted`; column `journal_visibility`) on every entry type, and
  `GET /api/me/journal` (already cross-gym). Also: Σχόλια (`journal_comments`), Σημείωση
  (`journal_notes`), immutable «Πώς νιώθω» check-ins (5 questions, 4-emoji scale), an injury
  timeline, workout content markers (`!instructions`, `!scaling`, `!safety`, `!equipment`,
  `!cue`, `!coach-brief`), messages to members (coaching message vs «message from the box»),
  and a six-tab staff member profile.
- **Εγώ:** Κοινοποίηση & ορατότητα, Ρυθμίσεις (personal theme, offline sync), gyms, join links.

---

## 5. What Phase 2 M1 built (PR #9)

The scope from the plan was places, the box profile and the filter pattern. All of it is done,
with acceptance met: the mockup-06 pattern is on Πρόγραμμα, a location can be pinned, and filters
are remembered.

### API
- **PostGIS (ADR-141).** `facility_locations` gained `point geography(Point,4326)` with a GiST
  index, plus `neighbourhood`, `city`, `country_code`, `opening_hours` (weekly spans, several per
  day) and `accessibility`. Compose, CI and backups use `postgis/postgis`. Migration
  `20261018100000_places_geo`.
- **Geocoding.** Port `Application.Ports.Geocoder` (`search/2`, `reverse/3`), with the adapter
  `Infrastructure.Facility.PhotonGeocoder`. The base URL comes from `PHOTON_BASE_URL`
  (default `https://photon.komoot.io`; **self-host it for production**). Photon only localises
  en/de/fr/it; other languages get local names. Neighbourhood is taken from district, then
  locality, then suburb. Routes: `GET /api/org/:slug/admin/geocode?q=`, `/geocode/reverse`,
  `/geocode/link?url=`, rate limited to 30 a minute and gated on the `manage_settings`
  capability. Failure returns 503 `geocoder_unavailable`.
- **Google Maps links.** `Facility.Domain.MapLink` reads `!3d…!4d`, then `@lat,lng`, then
  `q|query|ll|center|destination`. `HttpMapLinkResolver` expands short links (`maps.app.goo.gl`,
  `goo.gl`, `g.co`) following ≤4 redirects, **Google hosts only** (SSRF-safe). Errors return 422
  `not_a_map_link` or `map_link_unresolved`.
- **Places for members.** `ListBookablePlaces` (`GET /api/me/places`) returns the user's gyms'
  locations with distance (`GeoDistance`, `PlacePolicy`). Home location per membership comes
  from `SetHomeLocation` (`PUT /api/org/:slug/me/home-location`); staff set anyone's via
  `PUT …/admin/users/:id/home-location`.
- **Schedule data.** Class types gained a `level` (`beginner|all_levels|advanced`) and
  `audiences` (shared vocabulary, below). Each slot has a WOD focus computed from catalog
  movements (`Workouts.Domain.WorkoutFocus`): a tag needs ⅓ of the movements, and any olympic
  lift adds `olympic_lifting`. Booking terms now include the cancellation cutoff, and slots carry
  coach names and package coverage.
- **Saved filters (ADR-151).** `saved_filters(user_id, surface, kind, name, params,
  last_used_at)` stores the last-used params per surface (server-side, cross-device) and named
  filters. Validation is in `Identity.Domain.FilterPolicy`.
- **Media (ADR-148).** `media_objects` (account or tenant scope, purposes `box_photo`,
  `post_photo`, `body_photo`). Upload is a presigned PUT, then `CompleteMediaUpload` checks size
  and type and **rejects and deletes files that still carry EXIF/XMP**. An hourly
  `SweepOrphanMediaJob` (Oban cron) removes uploads that nothing references after a day.
- **Public profile (ADR-142).** `organization_public_profiles` is a **draft**.
  «Δημοσίευση» copies it to `published_snapshot`; visitors must only ever read the snapshot.
  Publishing needs text and at least one discipline (`missing` lists what's absent). Απόσυρση
  clears the snapshot and keeps the draft. Every write uses `lock_version`. Media are released
  only when neither the draft nor the snapshot uses them. Columns: `about`, `disciplines`,
  `services`, `audiences`, `languages`, `amenities`, `cover_photo_id`, `photo_ids` (≤12),
  `published_at`, `published_snapshot`.
- **Canonical vocabularies** live in code in `Organizations.Domain.BoxProfilePolicy`, served at
  public `GET /api/box-vocabulary` (cache 1 h):
  - **46 disciplines in 9 groups:** strength (strength, powerlifting, olympic_lifting,
    bodybuilding, strongman, kettlebell) · functional (crossfit, functional_fitness, hyrox, hiit,
    bootcamp, circuit_training, calisthenics, gymnastics) · endurance (running, indoor_cycling,
    cycling, rowing, endurance, ems_training) · mind_body (yoga, hot_yoga, pilates,
    pilates_reformer, barre, mobility, stretching, tai_chi_qigong) · combat (boxing, kickboxing,
    muay_thai, mma, bjj_grappling, wrestling, martial_arts, self_defense) · dance (dance,
    dance_fitness, pole_aerial) · aquatic (swimming, aqua_fitness) · outdoor (outdoor_training,
    climbing_bouldering) · recovery (physio_rehab, sports_massage, recovery).
  - **12 audiences:** beginners, women_only, kids, teens, over_40, seniors,
    prenatal_postnatal, adaptive, athletes, students, lgbtq_friendly, returning_from_injury.
    `returning_from_injury` requires `physio_rehab`. **Class types use the same audience list.**
  - **18 amenities:** showers, changing_rooms, lockers, towels, parking, bike_parking,
    public_transport_nearby, air_conditioning, sauna, cold_plunge, childcare,
    wheelchair_accessible, accessible_restroom, gender_neutral_restroom, wifi, water_refill,
    outdoor_area, drop_in_friendly.
  - **6 services:** personal_training, small_group_training, open_gym, nutrition_coaching,
    online_coaching, corporate.
  - **Languages:** ISO 639-1, up to 10.
  - Keys are never renamed. Labels live in the web `BoxTags` i18n namespace (12 locales).
    Migration `20261019100000` renamed `women`→`women_only` and `prenatal`→`prenatal_postnatal`,
    and moved `kids` from disciplines to audiences (profiles and class types).
- **Tag suggestions.** `profile_tag_suggestions` is a tenant table with RLS. `POST
  /api/org/:slug/admin/public-profile/suggestions` creates one. Platform staff review all gyms'
  suggestions at `GET/PATCH /api/platform/tag-suggestions` (via SECURITY DEFINER functions
  `milos_pending_tag_suggestions()` and `milos_resolve_tag_suggestion()`). «Added» only records
  the outcome. **Adding a tag is a code change** to `BoxProfilePolicy` plus 12 translations.

### Web
- **Member Box › Πρόγραμμα** (`/box/schedule`): built from plan §5a (two boards). It has the
  chip row with «Φίλτρα (n)» first and ✕ inside it, a full-screen filter page, the day view
  (week strip) and month grid behind the month name, a class bottom sheet with a fixed
  «Κράτηση», compact rows, out-of-package classes dimmed, a location title ▾ that opens the
  location picker (map behind a draggable list, «Σε αυτή την περιοχή» / «Πιο μακριά»), and
  filters remembered per gym. Components are in `components/member-app/box/schedule/*` and
  `components/filters/{FilterChipRow,FilterPage}.tsx`.
- **Admin location editor** at `/admin/settings/locations/[id]`. Order: name, address combobox
  (suggestions; a pasted Maps link resolves), neighbourhood (auto-filled until typed), a
  full-width MapLibre map with a draggable pin (tapping moves the pin), then hours (a row per
  weekday, «+» adds a span or splits off a 13:00–16:00 break, and «copy Monday to Tue–Fri»).
  The fixed footer has unsaved status, Cancel and Save. Components are in
  `components/admin/location/*`.
- **Admin public page editor** at `/admin/public-page`, linked from Ρυθμίσεις › «Δημόσια
  σελίδα». It has a status pill (Πρόχειρο / Δημοσιευμένη / Μη δημοσιευμένες αλλαγές), a
  checklist, «Δημοσίευση» (saves first, then publishes) and «Απόσυρση». The step tabs, numbered
  the first time, are Κείμενο · Φωτογραφίες · Τι προσφέρει · Για ποιους · Παροχές. Photos have a
  separate cover slot, then a gallery of up to 12 (reorder, ★ make cover, remove). The client
  re-encodes uploads (`lib/box-photo-upload.ts`: WebP or JPEG, ≤2400 px, which drops EXIF).
  Each tag card shows only the picked tags and opens `TagPicker`: a side panel on desktop and a
  bottom sheet on phones, with search (diacritic-insensitive), «Επιλεγμένα (n)», suggestions,
  collapsed groups with counts, «Τέλος» to apply, and «Δεν το βρίσκεις; Πρότεινέ το». Languages
  show common ones first, the rest are searchable by own, Greek or English name, max 10.
  Components are in `components/admin/public-page/*`.
- **Platform review** at `/platform/tag-suggestions` (linked from the platform organizations
  console).
- **i18n namespaces added:** `AdminLocation`, `AdminPublicPage`, `BoxTags`,
  `PlatformTagSuggestions`, plus `BoxSchedule` keys.
- **e2e:** `e2e/admin-location.spec.ts`, `e2e/admin-public-page.spec.ts` and the schedule specs,
  each run on the chromium and mobile-chrome projects.

### Known gaps and follow-ups from M1 (be honest with the owner about these)
1. **Languages are not pre-picked.** Board 3b Q6 says «Ελληνικά and English pre-picked»; the
   editor currently starts from what the profile holds. Pre-fill `["el","en"]` for a profile
   that has never been saved (`lock_version == 0`).
2. **The visitor view of the profile** (3b Q4: chips with «+N», a «Καλωσορίζει: …» line, amenity
   icons, languages by own name, empty sections hidden) is **not built**. It belongs to the
   public box page in **M2**. Amenity icons need choosing on the M2 board.
3. **«Φίλοι» chip** on Πρόγραμμα is waiting on follows (M2).
4. **Production geocoding** should point `PHOTON_BASE_URL` at a self-hosted Photon. The public
   komoot instance is fine for development only.
5. The e2e stubs duplicate the vocabulary groups. If `BoxProfilePolicy` changes, update
   `e2e/admin-public-page.spec.ts`.
6. In Playwright runs with stubbed APIs, the Next dev overlay shows "1 Issue". It comes from the
   `["my","entitlement"]` stub returning `{}` and is harmless.

---

## 6. Decisions register

### Phase 2 architecture decisions (plan §3)
| # | Decision | Taken | Status |
|---|---|---|---|
| D1 | Geo engine | PostGIS | **Built** (ADR-141) |
| D2 | Public box page without login | Public link: readable logged out, server-rendered for sharing; actions sign up first, then continue | Default taken; the card was never answered. **Confirm on the M2 board** |
| D3 | Following people | Approval for people; boxes and open clubs followed at once | Default taken; the card was never answered. **Confirm on the M2 board** |
| D4 | Map tiles | MapLibre GL, tile URL from `NEXT_PUBLIC_MAP_STYLE_URL`, default OpenFreeMap | **Built** (`lib/map-style.ts`) |
| D5 | Neighbourhoods | Pin + reverse geocode, editable | **Built** |
| D6 | Member groups | Channels of kind `member_group` inside the gym club; open clubs = clubs of kind `open` | For M4 |
| D7 | Trial acceptance | Automatic within the owner's caps; switchable to manual | For M3 |
| D8 | Body photos | Account-scoped private objects, SSE, short-lived signed URLs, consent record, deleted with the account, exported; never posted without a second confirmation | For M10 |
| D9 | Image privacy | Client re-encode + server EXIF/XMP rejection | **Built** (ADR-148; max edge 2400 px, not 2048) |
| D10 | Wallet and Garmin credentials | Built against fakes; real keys from runtime config; «Σύντομα» without them (platform capability, not per gym) | For M7, M13 |
| D11 | Health-like data retention | Kept until deleted; per-section delete-all; export JSON + photos zip | For M10–M11 |

### Product decision: other gyms (2026-10-17, plan §5a)
- Search by name always works, for everyone.
- **Paid shield add-on** for owners hides other gyms' trials and «Box με δοκιμαστικό» from
  their members with an active package. Events and open clubs from other gyms are unaffected.
- Without the shield, other gyms appear to active members **only** as one collapsed line at the
  end of Γύρω μου results: «Άλλα box στην περιοχή (n)». They are never a chip, never map pins,
  never in the feed or notifications.
- People with no active package see «Box με δοκιμαστικό» as a normal category.
- «Πιο μακριά» in the Πρόγραμμα location picker lists **only places the user can book**.
- **One home location per member** (default only; other locations of their gym stay
  bookable). Only the owner oversees all locations. Coaches and admins have a home location with
  a switch.

### Screen decisions
All screen-level decisions so far are in **plan §5a**:
- Box › Πρόγραμμα: 10 decisions from boards 1 and 2.
- Admin › locations and public «Σχετικά»: 8 decisions from boards 3 and 3b, including the tag
  vocabularies.

Treat §5a as binding. Do not re-ask what is settled there.

### Phase 1 decisions still in force (Phase 1 plan §3)
Community is its own context; no rollout flags; old URLs redirect; one visibility column on
every entry; the `#wod-σήμερα` leaderboard uses opt-ins; class-slot groups need ≥3 bookings in
28 days; moderation in Phase 1 was hide/delete only (the report queue comes in Phase 2 M4);
photos on posts come in Phase 2 M9.

### Text semantics (ADR-140; the owner reviewed them)
Σημείωση, Σχόλιο, Πεδίο, Coach note, Οδηγίες, Cue, Οδηγός coach, Μήνυμα and Ενημέρωση
τραυματισμού each have one meaning, one store and one component. The word «σημείωση» is only
for the member's Σημείωση and coach notes. Long form: Claude Doc «Σημειώσεις πριν και μετά το
redesign» (https://claude.ai/artifact/HqzttDjWXKGYnXAnr1WJc8).

### ADR register for Phase 2
The plan reserves ADR-141…151:
- Written: 141 Places, 142 Public profile, 148 Media, 151 Saved filters.
- Still to write as their milestones land: 143 open clubs and moderation, 144 events and
  trials, 145 QR and Wallet, 146 referral, 147 body and wellness, 149 devices, 150 cross-org
  journal.
- **142 covers only the profile so far.** Extend it in M2 with the public read API and follows.

---

## 7. Final mockups and visual references

### The design (source of truth)
`docs/product/mockups/milos-ia-mockup.html` has 34 clickable screens, a sitemap, coverage tables
and the anatomy atlas prototype. Each PNG in `docs/product/mockups/screens/` maps to a
milestone:

| Screen | Topic | Phase / milestone |
|---|---|---|
| 01 feed, 02 clubFeed | Feed, club feed | P1 done; M2 adds audiences, M9 photos |
| 03 club | Club page: Ροή · Κανάλια · Events · Μέλη | M4, M5 |
| 04 clubPublic | Public box page: Σχετικά · Πρόγραμμα · Events · Δημόσια, Ζήτα δοκιμαστικό, Ακολούθησε | **M2**, M3 |
| 05 near, 06 filters | Γύρω μου and the filter pattern | M6 (pattern done in M1) |
| 07 partners | Partners swipe | Phase 3 |
| 08 box | Box hub | P1 done |
| 09 checkin | QR check-in | M7 |
| 10 wodGoals, 11 atlas | WOD goals, anatomy atlas | Phase 3 |
| 12 start | Execution | Unchanged forever |
| 13 coachPT, 14 indie | PT with a gym coach, independent coach (Box title ▾) | M14 (provider switch); Phase 3 solo tier |
| 15 vault, 16 journal, 17 entry, 18 note | Journal | P1 done |
| 19 body, 20 measure | Σώμα | M10 |
| 21 wellness, 22 craving | Ευεξία, Λιγούρα | M11 |
| 23 progress | Πρόοδος | P1 done; M14 cross-org |
| 24–28, 31–33 Εγώ | Profile, PRs, clubs, privacy, payments, settings, help | P1 done; M2 followers |
| 29 buddy | Buddy για στήριξη | M12 |
| 30 devices | Συνδεδεμένες συσκευές | M7 (Wallet, ICS), M13 (Garmin) |
| 34 referral | Φέρε φίλο | M8 |

### UX boards (owner answers recorded in plan §5a)
| Board | URL | Covers |
|---|---|---|
| Πρόγραμμα | https://claude.ai/artifact/3mJnPApB49f3UXTcySjZaY | Filters, rows, views, remembering |
| Πρόγραμμα 2 | https://claude.ai/artifact/2DLyMwUaf4NxBAyc8wwDNG | ✕ placement, month grid, class sheet, location screen |
| Admin places (board 3) | https://claude.ai/artifact/JoK6kFLZ1bLnQGJSWSiURe | Location editor, pin, hours, public page flow, photos, publish |
| Admin tags (board 3b) | https://claude.ai/artifact/2KzyqpFmyX2gT1HgoJdeRw | Tag form, picker, visitor view, suggestions, languages |

The tag research (ClassPass, Urban Sports Club, Mindbody, Wellhub, Google Business Profile) is
in the project folder at `/mnt/project-files/phase-2/research/gym-tag-vocabularies.md`.

### As built (screenshots in the repo)
`docs/product/mockups/phase-2-built/`:
- `programma-day.png`, `programma-month.png`, `programma-filters.png`,
  `programma-location.png`, `programma-class-sheet.png`
- `desktop-` / `phone-admin-location.png`
- `desktop-` / `phone-admin-public-page.png`, `…-picker.png`, `…-photos.png`
- `desktop-` / `phone-platform-tag-suggestions.png`

---

## 8. Environment and the local gate

### Cloud session setup (Ubuntu 24.04 container)
- **Elixir:** OTP 27.3.4 from builds.hex.pm (ubuntu-24.04) and Elixir v1.18.4-otp-27 (zip). An
  env script lives at `/opt/beam/env.sh` in sessions that already installed it: run
  `source /opt/beam/env.sh` before any `mix` or `npm run generate:api`.
- **Postgres 16 + PostGIS:** `apt install postgresql-16-postgis-3`, then
  `service postgresql start` (or `pg_ctlcluster 16 main start`) and set the postgres password to
  `postgres`. There is no dev database; tests use the test database.
- **Playwright:** Chromium is at `/opt/pw-browsers/chromium`. Run with
  `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/opt/pw-browsers/chromium`. Set
  `SCHEDULE_SCREENSHOTS_DIR=<dir>` to capture screenshots. Never run `playwright install`.
- Hex hosts and the agent proxy are allowed. Gemini key: a project network secret (only relevant
  to PR #8).

### The gate (run before every PR; CI won't)
API (`apps/api`):
```
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix milos.architecture          # hexagonal boundaries
mix test                        # ~1560 tests, ~4–5 min
MIX_ENV=test mix ecto.rollback -n 1 && MIX_ENV=test mix ecto.migrate   # new migrations reversible
```
Web (`apps/web`):
```
npm run generate:api            # after any API schema change (needs beam env)
npx tsc --noEmit
npx eslint .
npm run i18n:check              # 12 locales, no untranslated English, no hard-coded copy
npx vitest run                  # ~690 tests
npx playwright test e2e/<spec>  # chromium + mobile-chrome
```

### Conventions that bite
- **API**
  - Hexagonal: controllers call Application services only.
  - Ports are configured in `config/config.exs`, with fakes in `test/support`.
  - **Every admin route needs an entry in `route_capabilities.ex`**, or it returns 403.
  - New error atoms map in `FallbackController`.
- **Tenancy**
  - Every table with `organization_id` needs RLS, plus a `TenantDataPolicy` entry and
    classification in `Infrastructure.Tenancy.Audit`, or `audit_test` fails.
  - Cross-tenant platform reads go through SECURITY DEFINER SQL functions.
- **OpenAPI** is contract-first (`open_api_spex`). Regenerate the web client after schema
  changes.
- **Web**
  - Admin pages wrap in `AuthGuard roles={["admin"]}` and use `useSession().tokens.access_token`
    and `adminHref(path, useOrganizationSlug())`.
  - `apiRequest` prefixes tenant-scoped paths with `/org/:slug` automatically.
  - Overlays use `z-[60]`. Maplibre loads via `dynamic(..., {ssr:false})`.
  - The CSP in `src/proxy.ts` limits image hosts to `NEXT_PUBLIC_MEDIA_ORIGIN` and map hosts;
    e2e image stubs must use an allowed origin (`http://media.localhost:18080`).
  - The platform console uses its own copy objects (`i18n/platform-organizations.ts`, en/el).
    Components rendered there must not call `useTranslations` unless the test wraps a provider.
- **i18n**
  - Every new string goes into all 12 catalogs (`en, el, ar, ru, de, es, pt-PT, he, it, bg, nl,
    fr`).
  - Write a small Python script that edits `messages/*.json` with OrderedDict,
    `ensure_ascii=False` and indent 2. Translations must be real: the checker rejects values
    equal to English unless they are brand or sport names.
  - Greek copy is neutral and non-judgmental («εκτός πλάνου», «λιγούρα»).
- **Repo search:** `.claude/CLAUDE.md` asks for the `vexp` MCP. When it isn't connected, use the
  built-in search tools.
- `apps/web/AGENTS.md`: this Next.js version differs from training data. Check
  `node_modules/next/dist/docs/` before using unfamiliar APIs.

---

## 9. What to do next: Phase 2 M2 (public box page, follows, audiences)

Plan §5 M2:
- `/api/public/boxes/:slug/*` and the web route `/b/[slug]` (Σχετικά · Πρόγραμμα · Events ·
  Δημόσια, mockup 04).
- `community_follows`, with follow requests in notifications.
- The audience picker gains `followers` and `public`.
- Εγώ shows followers and following.
- **Accept:** a logged-out visitor reads a published box, and Ακολούθησε works after sign-up.

Suggested order (same process as M1):
1. **Backend**
   1. An unauthenticated, rate-limited read API that serves **only `published_snapshot`**
      (never the draft) plus the published cover and photos, locations (point, neighbourhood,
      hours), the week's schedule read-only (trial availability lands in M3), open events (M5)
      and public posts.
   2. Slug aliases must resolve.
   3. `community_follows(follower_id, target_type user|organization|club, target_id, status
      requested|active)` with RLS, follow and unfollow, and approve or decline for people (D3).
   4. Feed query additions for `followers` and `public` audiences, and post audience
      validation.
   5. OpenAPI, then regenerate the web client.
   6. Extend ADR-142.
2. **UX board 4** (before any web code), covering:
   - the public page layout on phone and desktop;
   - how the visitor view renders tags (3b Q4 is decided; show it, don't re-ask);
   - amenity icons;
   - the cover and gallery viewer;
   - the logged-out CTAs (sign up, then continue, D2: confirm);
   - Ακολούθησε vs Ζήτα δοκιμαστικό placement;
   - the follow-request UX (D3: confirm), where requests appear, and the followers/following
     lists in Εγώ;
   - the audience picker with three options;
   - Open Graph preview.
   Record the answers in §5a.
3. **Web:**
   - `/b/[slug]`, server-rendered with OG tags, public, no AuthGuard;
   - the follow buttons and the requests inbox;
   - the audience picker;
   - Εγώ counts and lists;
   - turn on the «Φίλοι» chip in Πρόγραμμα.
4. **Fix the M1 gap 1** (pre-pick el and en) in the same PR, or in a small one first.
5. **Gate, PR,** then mark M2 in plan §9.

After M2 the order is M3 Trials → M4 Open clubs, member groups and moderation → M5 Events →
M6 Γύρω μου (with the other-gyms rules above) → M7 QR and Wallet → M8 Referral → M9 Media on
posts → M10 Σώμα → M11 Ευεξία and Λιγούρα → M12 Buddy → M13 Garmin → M14 Cross-org journal.
Each milestone gets backend, then a UX board, then web, then the gate, then a PR. M10–M12 must
pass the ethics checklist in plan §6.

### Open questions still waiting on the owner
1. D2 and D3 (above): confirm on the M2 board.
2. Plan §7: GDPR legal review of the consent copy before release; who pays for trial no-shows
   (default: a no-show counts against `per_person`); a Garmin developer account (owner action).
3. Brief §10: Greek market sizing; pricing tiers for gyms vs solo coaches; when to start the
   native wrapper.
4. TD-102 (platform subscriptions for owners) is still out of scope by owner decision. The
   «paid shield» add-on (other gyms) will need it, so raise it when M6 starts.

---

## 10. Quick facts

- Locales: 12. Greek is primary.
- The last ADR number used on the integration branch is 151. **ADR-152 is free** and is meant
  for PR #8's metering ADR. Use 153+ for anything new outside the plan's reserved set.
- Last tech-debt id: TD-105.
- API tests: 1559 green at the M1 merge. Web unit tests: 687 green.
- Owner's GitHub: `AnrPg`. Owner's name: Apostolos.
