# Redesign Phase 2: open up, under the owner's control

Date: 2026-10-17
Branch: milestone PRs into `redesign/social-centered` (Phase 1 merged to `main` with PR #7; the
redesign ships as `v2.0.0`).
Source of truth: `docs/product/2026-10-15-milos-product-vision-and-ia.md` (the brief, §9 v2 row) and
`docs/product/mockups/milos-ia-mockup.html` (screens 03–06, 09, 19–22, 29, 30, 34). The Greek write-up
`docs/product/Ο χάρτης του Milos.md` (2026-10-17) agrees with both and is used for copy.
Phase 1 plan: `docs/plans/redesign-phase-1-member-app.md` (what exists).

Pitch: «Φέρνεις νέους πελάτες με τους δικούς σου όρους.»

## 1. Goal and scope

Open the gym's club to the outside world without taking control away from the owner, and give the
athlete a journal that covers body and wellbeing across every provider.

### In scope (brief §9, v2 row)
- **Places and discovery:** coordinates and neighbourhoods for locations, the public box page
  (Σχετικά · Πρόγραμμα · Events · Δημόσια, mockup 04), `Γύρω μου` with the chip row +
  `Φίλτρα (n)` pattern and saved filters (mockups 05, 06).
- **Follows and audiences:** follow a box / open club, follow a person (with approval, D3), post
  audiences `followers` and `public` (brief §7.1, §8.2).
- **Open clubs and member groups:** staff-created open clubs, member groups with the owner's
  Όχι · Με έγκριση · Ελεύθερα setting, join by request, report → staff queue, archive, 60-day
  auto-archive (§7.1 governance table, mockup 03).
- **Events:** club events with capacity, price, open to non-members, guest pass, `Θα έρθω`, invite.
- **Trial-slot policy:** per-week / per-person caps set by the owner, `Ζήτα δοκιμαστικό`,
  `Κλείσε με δοκιμαστικό` on the public schedule.
- **QR check-in + Wallet:** rotating door QR on the existing check-in desk, scan resolution
  (booking −30′/+15′ → open gym → trial offer), personal in-app QR, Apple/Google Wallet pass
  (§7.5, mockup 09), `Εγώ › Συνδεδεμένες συσκευές` (mockup 30).
- **Member referral:** `Εγώ › Φέρε φίλο` and `Box › Συνδρομή`: link + QR, invite to an event,
  automatic attribution through join links, stages signup → trial → paid, rewards from the active
  programme approved by the admin as today (§7.9, mockup 34).
- **Σώμα:** measurement snapshots, private photos (front/side/back) with ghost outline, compare
  slider, chart per metric (§7.7, mockups 19, 20).
- **Ευεξία:** `Σήμερα` card (water, sleep, meals, mood/stress, Λιγούρα), week strip, coach plan
  macros that can be hidden (§7.7, mockups 21, 22).
- **Buddy για στήριξη** (§7.8, mockup 29).
- **Garmin** (web, cloud API): activities and sleep into the journal.
- **Cross-org unified journal:** Πρόοδος, history and filters across every provider; Box title ▾
  switches providers and the today card merges items from all of them (§7.10).
- **Phase 1 deferrals:** photos on posts (D9), report → staff queue (D8), Γύρω μου toggle
  (stable-screen rule kept it out of Phase 1).
- **Ρυθμίσεις additions** that Phase 2 data needs: units, journal sections on/off, weight as trend
  only (§7.11, §8.6).

### Non-goals (Phase 3, do not build; do not block)
Partners/swipe, seasons and `#season` channels, WOD goals + anatomy atlas, advanced analytics
(coverage, qualities, load, insights), PT squads, solo-coach tier and pricing, native wrapper
(Apple Health, Health Connect, widgets, geofence, NFC), AI coach assistant.
Keep the enums open for them: club kinds `pt_squad | season` and channel kind `season` already
exist (ADR-138); device providers are an enum with `apple_health | health_connect` reserved.

## 2. What exists today (Step 1 findings, 2026-10-17)

| Need | Exists | Gap |
|---|---|---|
| Geo | `facility_locations(name, address)`; Postgres 16 without PostGIS | Coordinates, neighbourhood, geo index, map picker |
| Box profile | `organization_settings` (brand name/logo/colour, free `settings` map) | About, disciplines, photos, hours, public flag |
| Unauthenticated API | `/api/auth/join/:slug`, slug aliases, ICS feed, theme | Public box page, public schedule, public events, public posts |
| Clubs | `community_clubs` with kinds `gym|open|member_group|pt_squad|season`, `join_policy`; only gym clubs are used; members derived from Organizations (ADR-138 §2) | Explicit memberships for non-derived clubs, non-member read policy, member-group channels, requests |
| Posts | `audience` column, only `club_channel` used; text + journal attachment | `followers`/`public`, media, report queue |
| Check-in | Open-gym self/staff check-in (`facility_check_ins`), class booking check-in, staff desk `/admin/check-in` | Door token, scan resolution, personal QR, Wallet pass |
| Bookings | Guest passes (`guest_name`), waitlist, allowances `class_visits|event_visits|guest_passes` | Trial bookings for non-members, trial caps |
| Referral | `referral_programs/events/rewards` (admin only, manual) | Member link/QR, attribution in join, stage transitions, member view |
| Wellbeing | Injuries, readiness check-ins (sleep, energy, mood, stress, body, M5.1) | Water, sleep duration, meals, cravings, buddy |
| Body | Nothing | Snapshots, photos, consent, retention |
| Storage | MinIO via `ex_aws_s3`, `TenantObjectStorage` (tenant prefix), avatar and logo uploads | Account-scoped private objects, post media |
| Journal | `GET /api/me/journal` already cross-gym (ADR-139 §9); Vault account-scoped | `/org/:slug/me/progress` and `/me/history` are org-scoped |
| Devices | ICS feed | Garmin, Wallet |

## 3. Decisions

Cards posted 2026-10-17; work proceeds on the recommended option unless the answer differs.

| # | Decision | Default taken | ADR |
|---|---|---|---|
| D1 | Geo engine | **PostGIS** (`postgis/postgis:16-3.5-alpine` in compose, CI, backup jobs); `geography(Point, 4326)` + GiST | ADR-141 |
| D2 | Public box page without login | **Public link**: readable logged out (server-rendered for sharing); actions sign up first and then continue | ADR-142 |
| D3 | Following people | **Approval**: a follow of a person is a request; boxes and open clubs are followed at once | ADR-142 |
| D4 | Map tiles | MapLibre GL with a tile URL from config (`NEXT_PUBLIC_MAP_STYLE_URL`), default OpenFreeMap; no vendor lock, no key in the repo | ADR-141 |
| D5 | Neighbourhoods | Owner picks the location pin; neighbourhood is a normalised name stored on the location, chosen from a suggestion list (reverse geocoding when a geocoder is configured, else typed) | ADR-141 |
| D6 | Member groups | Channels of kind `member_group` inside the gym club (mockup 03 lists them under the club's Κανάλια), not separate clubs; open clubs are clubs of kind `open` | ADR-143 |
| D7 | Trial acceptance | Automatic while the owner's caps allow it; the owner can switch to manual approval | ADR-144 |
| D8 | Body photos | Account-scoped (never tenant-scoped) private objects, server-side encryption, short-lived signed URLs, explicit consent record on first upload, deleted with the account, included in the export; never in posts without a second confirmation | ADR-147 |
| D9 | Image privacy | Every uploaded image is re-encoded client-side (canvas → JPEG/WebP, max 2048 px), which drops EXIF/GPS; the server rejects files whose markers still carry EXIF/XMP | ADR-148 |
| D10 | Wallet and Garmin credentials | Built and tested against fakes; real certificates/keys come from runtime config (Apple Pass Type ID + WWDR, Google Wallet issuer service account, Garmin Health API keys). Without them the matching row in Συνδεδεμένες συσκευές shows «Σύντομα» (platform capability, not a per-gym flag) | ADR-145, ADR-149 |
| D11 | Health-like data retention | Kept until the user deletes it or the account; per-section delete-all; export as JSON + photos zip | ADR-147 |

## 4. Architecture (ADR candidates)

### ADR-141 Places and geo search
- Migration enables `postgis`; `facility_locations` gains `point geography(Point,4326)`,
  `neighbourhood`, `city`, `country_code`, `opening_hours jsonb` (weekly spans), `accessibility text[]`;
  GiST index on `point`.
- `Places` read model (`Application.SearchNearby`): one query per kind (boxes, open clubs, events,
  public posts) with `ST_DWithin(point, :origin, :radius)` and the kind's filters, merged and ordered
  by `ST_Distance`/time. Origin = browser geolocation, a saved place, or the centroid of the chosen
  neighbourhoods. The client never sends more precision than 3 decimals (≈100 m).
- Admin › Τοποθεσίες: map pin picker + neighbourhood; `Γύρω μου` map view in the same component.

### ADR-142 Public surfaces and follows
- `organization_public_profiles(organization_id, published_at, about, disciplines text[],
  photos[], languages text[], audiences text[], price_hint)`; a box appears publicly only when the
  owner publishes it.
- Unauthenticated, rate-limited read API under `/api/public/boxes/:slug` (profile, schedule of the
  week read-only with trial availability, open events, public posts). Web route `/b/[slug]`
  server-rendered with Open Graph tags.
- `community_follows(follower_id, target_type user|organization|club, target_id, status
  requested|active, inserted_at)`; RLS: follower and target read their rows.
- Post audiences: `club_channel(id)` (Phase 1), `followers`, `public`. Feed query adds followed
  authors' `followers` posts and followed boxes'/clubs' `public` posts in `Τα clubs μου`.

### ADR-143 Open clubs, member groups and moderation
- Open clubs: `community_clubs.kind = open`, created by staff, explicit
  `community_club_memberships`, `join_policy open|approval`; read policy for non-members on
  public open clubs.
- Member groups: channel kind `member_group` with `created_by_id`, `join_policy open|request`,
  `status pending_approval|active|archived`; owner setting
  `community.member_groups = none|approval|free` (default `approval`).
- `community_reports(target_type post|comment|channel, target_id, reporter_id, reason, status,
  resolved_by_id)` → staff queue in the console and in Box › Πελάτες μου for coaches.
- `ArchiveInactiveGroupsJob` (daily): member groups with no post for 60 days → archived.

### ADR-144 Events and trials
- `community_events(club_id, organization_id, title, description, starts_at, ends_at,
  location_id | place, capacity, price_cents, open_to_non_members, guest_pass_allowed,
  cancelled_at)` + `community_event_attendees(event_id, user_id, status going|waitlisted|cancelled,
  source)`.
- `scheduling_trial_policies(organization_id, per_week, per_person, approval auto|manual,
  class_type_ids)` and `scheduling_trial_requests(organization_id, user_id, scheduled_class_id?,
  status requested|accepted|declined|attended|converted, referral_event_id?)`; a trial booking is a
  booking with `kind = trial` that draws no allowance.

### ADR-145 QR check-in and Wallet
- `facility_door_tokens`: no table; tokens are `HMAC(location_secret, location_id ‖ 30-s window)`
  with ±1 window grace; `facility_locations.door_secret` rotates on demand.
- Deep link `/c/<location>/<token>` → `POST /api/check-in/scan` → `ResolveScan` (booking within
  −30′/+15′ → class check-in; else open gym if the package allows; else non-member → trial offer).
- Personal QR: signed short-lived member token scanned by the desk (same resolver, actor = staff).
- Wallet: `Wallet.PassBuilder` port with Apple (`.pkpass`, signed PKCS#7) and Google (JWT save
  link) adapters; the pass barcode carries a long-lived member token, revocable.

### ADR-146 Member referral
- `referral_links(organization_id, user_id, code)`; join link accepts `?ref=code`, registration
  stores the referral and creates a `referral_event` (stage `signed_up`); stage moves on first
  trial (`trial`) and first paid membership (`paid`), from existing domain events. A reward is
  created from the active programme on `paid` with status `pending` for admin approval.

### ADR-147 Body and wellness data
- `body_snapshots(user_id, taken_at, metrics jsonb, photo_keys, visibility, notes)` (account-scoped,
  personal-session RLS, coach read only when shared, audited like coach notes).
- `wellness_entries(user_id, kind water|sleep|meal, occurred_on, value jsonb, source manual|garmin,
  visibility)`; `craving_entries(user_id, intensity, triggers[], outcome, support_requested, at)`.
- `user_health_consents(user_id, scope body_photos|health_data, granted_at, withdrawn_at)`.
- Settings: units (metric/imperial), `journal_sections` (body, wellness, cravings on/off),
  `weight_display number|trend`.
- Journal feed kinds gain `body`, `wellness`, `craving` (private by default, ladder applies).

### ADR-148 Media
- `media_objects(owner_id, scope account|tenant, purpose post|body_photo|box_photo, key,
  content_type, width, height, bytes, status pending|ready, inserted_at)`; presigned PUT, then
  `CompleteUpload` verifies size, type and absence of EXIF before `ready`.
- Posts get `media_ids` (≤4); body snapshots reference `body_photo` objects.

### ADR-149 Device integrations
- `device_connections(user_id, provider garmin|apple_health|health_connect, status, tokens
  (encrypted), last_synced_at)`; Garmin OAuth 2 PKCE, push notifications to
  `/api/integrations/garmin/push`, Oban ingest job; activities → `training_log_entries` with
  `source = garmin` (dedupe by provider id), sleep → `wellness_entries`.

### ADR-150 Cross-org journal read model
- Progress and history become account-level queries (`/api/me/progress`, `/api/me/history`) in
  the member's personal session over every membership (same RLS predicate as the journal feed);
  Box title ▾ lists providers from `/api/memberships`, and the today card asks each provider.

### ADR-151 Filters and saved filters
- `saved_filters(user_id, surface, name, params jsonb, last_used_at)`; last-used params per surface
  remembered server-side so they follow the user across devices.
- Web: one `FilterChipRow` + `FilterSheet` driven by a per-surface schema; used by Γύρω μου,
  Box › Πρόγραμμα, Feed/club, Ημερολόγιο, Vault and Πρόοδος.

## 5. Milestones (each one PR into `redesign/social-centered`)

Order follows dependencies: places and public surfaces first, because events, trials, Γύρω μου,
check-in and referral all need them.

### P2-M1 · Places, box profile and the filter pattern (A + W)
- PostGIS image swap (compose, CI, backup jobs); location point, neighbourhood, hours; admin map
  picker; `organization_public_profiles` and admin editor (Σχετικά content, photos via ADR-148);
  `saved_filters` API; `FilterChipRow`/`FilterSheet`; apply the pattern to Box › Πρόγραμμα
  (location, class type, coach, time, only with spots, only covered by my package).
- Accept: mockup 06 pattern on Πρόγραμμα; a location can be pinned; filters remembered.

### P2-M2 · Public box page, follows and audiences (A + W)
- `/api/public/boxes/:slug/*`, `/b/[slug]` (Σχετικά · Πρόγραμμα · Events · Δημόσια, mockup 04),
  `community_follows`, follow requests in notifications, audience picker gains `followers` and
  `public`, Εγώ profile shows followers/following.
- Accept: a logged-out visitor reads a published box; Ακολούθησε works after sign-up.

### P2-M3 · Trials (A + W)
- Trial policy (admin), `Ζήτα δοκιμαστικό` and `Κλείσε με δοκιμαστικό`, trial requests queue,
  trial booking kind, conversion tracking.

### P2-M4 · Open clubs, member groups, moderation (A + W)
- Club page tabs Ροή · Κανάλια · Events · Μέλη (mockup 03), member groups with owner setting and
  requests, report queue, archive job, `+ Βρες` in the club bar.

### P2-M5 · Events (A + W)
- Events per club, `Θα έρθω`, capacity/waitlist, guest pass, invite, event card in Ροή and on the
  public page.

### P2-M6 · Γύρω μου (A + W)
- Scope toggle (remembered), nearby search over events, open clubs, boxes with trial and public
  posts, filters of brief §7.2, saved combinations, list + map (mockup 05).

### P2-M7 · QR check-in and Wallet (A + W)
- Door display mode on the check-in desk, scan deep link and resolver, Box › Check-in personal QR
  (mockup 09), Wallet passes, Εγώ › Συνδεδεμένες συσκευές (mockup 30, with ICS).

### P2-M8 · Member referral (A + W)
- Εγώ › Φέρε φίλο (mockup 34), Box › Συνδρομή entry, attribution and stages, rewards view.

### P2-M9 · Media and photos on posts (A + W)
- ADR-148 pipeline (also used by M1 box photos), up to 4 photos per post, report queue covers them.

### P2-M10 · Σώμα (A + W)
- Snapshots, Μέτρηση form (mockup 20), consent, ghost outline camera, compare slider, charts,
  weight-as-trend setting, units.

### P2-M11 · Ευεξία Σήμερα and Λιγούρα (A + W)
- Water, sleep, meals (in/out of plan, optional photo), cravings (mockup 22), coach plan macros
  hideable, week strip, sections on/off, ethics rules of §8.6.

### P2-M12 · Buddy για στήριξη (A + W)
- Invite/accept/leave, «Χρειάζομαι στήριξη» with quick replies, optional weekly counts summary,
  coach summary only with permission (mockup 29).

### P2-M13 · Garmin (A + W)
- OAuth, push ingest, dedupe, devices row status.

### P2-M14 · Cross-org journal and provider switch (A + W)
- Account-level Πρόοδος and history, journal and Vault filter rows, Box title ▾ with merged today
  card and source labels.

**How each milestone runs (Apostolos, 2026-10-17):** the fine details of every screen are not decided.
Each milestone builds its backend first (data, API, OpenAPI); then, before any screen is written,
Claude opens an interactive UX conversation about that screen, records the outcome in §5a, and only
then builds the web side from those decisions. The mockup gives direction, not a pixel spec.

Every milestone: tests first where practical; compile, format, credo, type-check and lint per
slice; full API and web suites once at the end of the milestone; OpenAPI regenerated; all copy in
the 12 locales (`npm run i18n:check`).

## 5a. UX decisions (filled in per screen, from the UX conversations)

Sessions run on mockup boards (published artifacts with alternatives to pick and comment on), per
Apostolos' preference to decide on visuals rather than text.

### Box › Πρόγραμμα (2026-10-17, [board](https://claude.ai/artifact/3mJnPApB49f3UXTcySjZaY))

1. **Filter row:** one horizontally scrolling chip row under the title. «Φίλτρα (n)» is the first
   chip; nothing is pinned, the row scrolls away as a whole. *Pending: «Καθαρισμός» as a second
   chip, or a ✕ inside «Φίλτρα (n)».*
2. **Which filters, where:**
   - **Chips on the row:** Είδος μαθήματος, Μαθήματα ή events, Διαθεσιμότητα, Πακέτο, Επίπεδο,
     Φίλοι.
   - **Only in Φίλτρα:** Coach, Ώρα, Οι κρατήσεις μου, Διάρκεια, Εστίαση προπόνησης, Κοινό.
   - **Not offered:** Ημέρες (confusing next to the date strip), Γλώσσα, Κόστος.
   - Διαθεσιμότητα options: Έχει θέσεις · Πλήρη (με λίστα αναμονής) · Πλήρη · Όλα.
   - Οι κρατήσεις μου options: Όλα (default) · Μόνο όσα έκλεισα · Έκλεισα ή περιμένω σε αναμονή;
     own bookings always carry a ✓ in the list.
   - Tapping a multi-option chip opens a **small menu under the chip**; on/off chips just toggle.
   - New data this needs: a level and audience tag per class (series/type), and the WOD focus
     derived from the posted workout's movements.
3. **«Φίλτρα (n)»** opens a **full-screen page** (sections per filter, «Καθαρισμός» and «Δείξε N»
   at the bottom).
4. **Classes outside the package** (when «Στο πακέτο μου» is off): shown **dimmed** with an
   «Εκτός πακέτου» tag.
5. **Time filter:** a **from–to range** slider.
6. **Location:** the schedule shows the location in the **title as a switch ▾**. Tapping it opens a
   **location picker screen**: an accurate street map on top (gym name over each pin) and a list in
   two sections, «Σε αυτή την περιοχή» (locations in the map frame, live as you pan or zoom) and
   «Πιο μακριά» (all others), sorted by distance from the user (device location if allowed, else the
   user's neighbourhood), with distance on each row.
   «Πιο μακριά» lists **only places the user can book** (their gym's locations and gyms they are a
   member of). Where users discover other gyms at all is a separate decision (see below).
7. **Layout:** the **day view** (week strip, one day's classes) is the default. A subtle view switch
   offers a **month grid** with dots counting each day's classes; tapping a date opens the day view
   on that date. Tapping a class opens an **overlay** with class info (time, duration, coach, spots,
   Κράτηση) and the WOD, its parameters in collapsed sections revealed progressively.
8. **Class row:** **compact** (time, name, coach, spots) plus a subtle duration («18:00 · 60′»);
   location only when several locations are shown.
   **Product rule:** members experience their gym as **one home location** (gyms with several
   locations usually have a separate entry per location); only the owner oversees all locations.
   Needs a per-membership home location. The home location is the **default only**: members can
   still view and book other locations of their gym from the picker. Coaches and admins also have
   one home location, with a switch when they work at several.
9. **Remembering:** last filters restored silently per gym (saved_filters `box_schedule`),
   «Καθαρισμός» always first.
10. **No results:** a prominent «Δεν υπάρχουν μαθήματα» for the chosen date, with the next match as
    one quiet line beneath.


## 6. Ethics and safety checklist (brief §8.6, applies to M10–M12)
- [ ] No calories by default; macros only with a coach plan and hideable
- [ ] Weight as trend only option
- [ ] Neutral copy: «εκτός πλάνου», «λιγούρα»
- [ ] No leaderboard or public comparison for weight, body or diet
- [ ] Body, wellness and cravings sections can each be switched off
- [ ] Insights labelled as indicators, never medical advice
- [ ] Photos never posted without a separate confirmation

## 7. Open questions
1. Brief §10 Q5 (GDPR for photos and health-like data): defaults in D8/D11; a legal review should
   confirm consent copy before release.
2. Who pays for trial no-shows (count against `per_person`?). Default: a no-show counts.
3. Garmin Health API access requires an approved developer account (owner action).

## 8. Environment notes
- Cloud session: OTP 27 + Elixir 1.18.4 from builds.hex.pm, Postgres 16 + `postgresql-16-postgis-3`
  from apt.

## 9. Progress
- [x] Step 1 explore · [x] Step 2 decisions (cards posted, defaults in §3) · [x] Step 3 plan
- [ ] P2-M1 · [ ] P2-M2 · [ ] P2-M3 · [ ] P2-M4 · [ ] P2-M5 · [ ] P2-M6 · [ ] P2-M7 · [ ] P2-M8
- [ ] P2-M9 · [ ] P2-M10 · [ ] P2-M11 · [ ] P2-M12 · [ ] P2-M13 · [ ] P2-M14
