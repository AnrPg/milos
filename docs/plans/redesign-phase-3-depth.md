# Redesign Phase 3: depth and the second market

Date: 2026-10-21
Branch: milestone PRs into `redesign/social-centered`, one branch and one PR per milestone.
Source of truth: `docs/product/2026-10-15-milos-product-vision-and-ia.md` (brief §9 v3 row, §7.3,
§7.6, §7.7 analytics catalog, §7.10, §8.4, §8.6) and `docs/product/mockups/milos-ia-mockup.html`
(§ "Στόχοι WOD" atlas prototype, Πρόοδος screens).
Phase 2 plan: `docs/plans/redesign-phase-2-open-up.md` (what exists; its non-goals are this scope).

Pitch: «Πουλάς προγράμματα, όχι μόνο συνδρομές.»

## 1. Goal and scope

Give the athlete depth (what each workout trains, what their training adds up to) and give the
owner new things to sell (seasons, PT squads), then open a second market: the independent coach.
Native capabilities and the AI layer come last, on top of data that already exists.

### In scope (brief §9, v3 row)
- **WOD goals:** coach toggle «Εμφάνιση στόχων στα μέλη», goals auto-suggested from the exercises
  (muscle groups with role, the 10 fitness qualities, stimulus text), athlete ticks what they felt
  in the log (§7.6).
- **Anatomy atlas:** region → muscle group → head, what it does, own sets over 4 weeks, exercises
  from the gym library, heat-map mode; reached from goals and `Πρόοδος › Μυϊκή κάλυψη` (§7.6).
- **Advanced analytics:** muscle coverage and balance, qualities radar, training load (sRPE,
  acute:chronic as an indicator), insights (sleep ↔ performance, time of day, cravings, hydration),
  only after enough data and labelled as indicators (§7.7).
- **Seasons:** sellable fixed-length programmes (Hyrox prep, 12-week challenge) with a `#season`
  channel created on sale, the programme in the journal, `Box › Συνδρομή › seasons` (§6.2, §7.1).
- **PT squads:** invite-only coach + clients channel, from `Box › Πελάτες μου` (§7.1, §7.10).
- **Partners:** swipe only inside a club, mutual match → message → «Κλείστε μαζί», report/block,
  optional gender preference, framed as training partner (§7.3, §8.6).
- **Solo-coach tier:** the independent trainer as a one-person organization with its own
  onboarding, Box layout «Νίκος Π. · Personal coach ▾», session packages and a smaller SaaS tier
  (§5.3, §7.10).
- **Native wrapper:** store apps around the PWA; Apple Health, Health Connect, home-screen widgets
  («+1 νερό»), geofenced check-in, NFC (§8.4).
- **AI coach assistant as a layer:** scaling suggestions from injuries and voice logging; the
  coach approves anything that reaches an athlete's programme (§9).

### Non-goals (later, do not build; do not block)
Promoted events and featured placement in `Γύρω μου`, revenue share on paid seasons, online card
payments, a fifth `Clubs` tab (brief §9 validation rule), AI that writes whole programmes.

## 2. What exists today (to confirm in Step 1)

| Need | Exists | Gap |
|---|---|---|
| Exercise taxonomy | `exercise_catalog_entries.muscle_groups`, `movement_pattern`, `skill_domain`; `InjuryRiskPolicy` maps exercises to regions (primary/secondary) | Head-level muscles, region ↔ group ↔ head tree, fitness-quality mapping |
| Workout goals | Nothing | `WorkoutGoals`, `GoalFeedback`, editor toggle |
| Atlas art | Mockup prototype; anatomy-models confirmed (D2), test renders in `/mnt/project-files/body-atlas/` | Licensed SVG/mesh assets, mapping to the taxonomy |
| Load data | `training_log_entries.perceived_effort`, `duration_seconds` | Load read model, acute:chronic |
| Insight inputs | Sleep and wellness entries (M11), cravings, PRs, Garmin sleep (M13) | Correlation jobs, data-sufficiency gate |
| Clubs | Kinds `pt_squad`, `season` and channel kind `season` reserved (ADR-138) | Creation flows, membership sources |
| Selling | Packages, allowances, corporate plans, staff-recorded payments; no card processor | Season product with dates, capacity and sale → channel |
| Independent coach | `POST /api/organizations`, provider switch (M14) | Org kind/tier, onboarding, coach-centred Box |
| Devices | `device_connections` with `apple_health`, `health_connect` reserved (ADR-149), Garmin live | Native bridge, ingest from the phone |
| AI | Per-gym opt-in assistant with encrypted key behind `WorkoutTextAnalyzer` (ADR-138 plan), `ai_usage` metering | Scaling-suggestion port, approval queue, speech-to-text |

## 3. Decisions (defaults; cards posted at Step 2)

| # | Decision | Default taken | ADR |
|---|---|---|---|
| D1 | Muscle taxonomy | Extend the existing catalog with a head-level tree; never a parallel taxonomy (brief §7.6) | ADR-163 |
| D2 | Atlas assets | **Confirmed by ANR (2026-10-21):** anatomy-models (Z-Anatomy glTF, CC BY-SA 4.0, pinned commit ac52bab, `muscles.glb` 3.8 MB, nodes `ta2-<id>.<l\|r\|m>`, heads split) rendered in three.js; attribution in the app; asset manifest keyed by TA2 ids | ADR-164 |
| D3 | Goal suggestions | Deterministic from the catalog (sets × role weights); the AI layer may refine later, never required | ADR-163 |
| D4 | Insight threshold | ≥4 weeks and a minimum sample per insight; every insight carries «Ένδειξη, όχι ιατρική συμβουλή» | ADR-166 |
| D5 | Season sale | A season is a package with dates and capacity; purchase is a request the staff confirm, like today's packages (no card processor) | ADR-167 |
| D6 | Partners visibility | Opt-in per club, hidden by default; profile shows first name, level, times, goal; no photos beyond the avatar | ADR-169 |
| D7 | Solo-coach pricing | Tier as a platform entitlement on the organization; prices are a config table that ANR fills (brief §10 Q2) | ADR-170 |
| D8 | Native wrapper | Capacitor around the existing Next.js app (same code, same deploy), native plugins only for what web can't do | ADR-171 |
| D9 | AI provider | Provider-agnostic ports, reusing the per-gym key and `ai_usage` metering; off unless the gym enabled the assistant | ADR-174 |
| D10 | Voice logging | Speech-to-text through the same provider port; audio is never stored after transcription | ADR-175 |

## 4. Architecture (ADR candidates)

### ADR-163 WOD goals
- `muscle_regions`, `muscle_groups`, `muscle_heads` reference tables (seeded, versioned) linked to
  catalog entries with role `primary|secondary|stabilizer`; `fitness_qualities` (the 10 skills)
  mapped from `skill_domain` and movement pattern.
- `workout_goals(workout_id, muscles jsonb [{head_or_group, role}], qualities[], stimulus,
  visible_to_members, suggested_version)`; `SuggestWorkoutGoals` from the parsed exercises.
- `goal_feedback(training_log_entry_id, felt_muscles[], felt_qualities[])`, private by default,
  visibility ladder applies.

### ADR-164 Anatomy atlas
- Asset manifest (SVG front/back per level, ids keyed to the taxonomy), attribution screen,
  lazy-loaded per level. `GET /api/me/atlas?range=4w` returns sets per node; exercises per node from
  the gym library with video links.

### ADR-165 Coverage, qualities and load read models
- `Analytics.MuscleCoverage` (sets per group, push/pull and quad/ham ratios, from logs × catalog ×
  felt feedback), `Analytics.QualitiesRadar`, `Analytics.TrainingLoad` (daily sRPE, 7/28-day
  acute:chronic, overload indicator band). Account-level, over every provider (ADR-162).

### ADR-166 Insights
- `InsightRule` behaviour (inputs, minimum sample, compute, copy key); nightly Oban job writes
  `user_insights(user_id, rule, period, value jsonb, computed_at)`; rules for sleep ↔ PRs, time of
  day, cravings triggers, hydration. Sections switched off in Ρυθμίσεις produce no insights.

### ADR-167 Seasons
- `season_offerings(organization_id, title, starts_on, weeks, capacity, price_cents, programme_id,
  coach_ids[], status)` + `season_enrollments(user_id, offering_id, status requested|active|
  completed|cancelled)`; confirmation creates a club of kind `season` (or a `season` channel in the
  gym club) and schedules the programme into the member's Box and journal.

### ADR-168 PT squads
- Club kind `pt_squad`, created by a coach, invite-only memberships from the coach's client list;
  leaving a coaching relationship removes the member.

### ADR-169 Partners
- `partner_profiles(user_id, club_id, active, level, times[], goals[], gender_preference?)`,
  `partner_swipes(swiper_id, target_id, club_id, direction, at)`, `partner_matches` created on
  mutual like; match opens a Partners thread in Μηνύματα; report/block reuse the community report
  queue; eligibility = verified active membership of the club, re-checked on every read.

### ADR-170 Solo-coach tier
- `organizations.kind gym|independent_coach` and `platform_tier` entitlement; onboarding flow for an
  independent coach (profile, services, session packages, optional «Team» club and open bootcamps);
  Box renders coach layout for that kind.

### ADR-171 Native wrapper
- Capacitor shell (`apps/mobile`), deep links and universal links for `/c/…` and join links,
  native push alongside web push, feature detection in the web app (`platform.capabilities`).

### ADR-172 Phone health data
- HealthKit and Health Connect plugins read workouts, sleep, steps, weight; batched upload to
  `/api/integrations/phone-health/ingest` with the same dedupe and `source` labels as Garmin.

### ADR-173 Widgets, geofence, NFC
- Widgets: «+1 νερό», today's WOD, check-in, driven by a small signed widget token API.
- Geofence: region per location (ADR-141 point + radius), local notification → the same
  `ResolveScan` path; NFC tag carries the door deep link.

### ADR-174 AI scaling suggestions
- `ScalingAdvisor` port: input = programmed workout + the athlete's active injuries and history;
  output = per-movement substitutions with reasons. Suggestions land in a coach approval queue in
  `Box › Πελάτες μου`; only approved ones become ADR-050 modification patches.

### ADR-175 Voice logging
- Record → transcribe → reuse the free-text parser → editable draft entry; nothing is saved until
  the athlete confirms.

## 5. Milestones (each one PR into `redesign/social-centered`)

Order follows dependencies: taxonomy and goals feed the atlas and analytics; selling features
before the second market; the native shell before the native features; AI last.

### P3-M1 · WOD goals (A + W)
- Taxonomy tables and seeding, goal suggestion, editor toggle, goals on the workout card, «τι
  ένιωσες» checklist in the log.

### P3-M2 · Anatomy atlas (A + W)
- Assets and manifest, 3-level navigation, heat-map mode, node detail with own sets and library
  exercises; entry from goals.

### P3-M3 · Coverage, qualities and load (A + W)
- Πρόοδος sections Μυϊκή κάλυψη (links into the atlas), qualities radar, training load with
  indicator band; filters and time range as in Phase 2.

### P3-M4 · Insights (A + W)
- Insight rules and nightly job, Πρόοδος insights section, sufficiency empty states, ethics labels.

### P3-M5 · Seasons (A + W)
- Admin season builder, `Box › Συνδρομή` seasons list and request, `#season` club/channel on
  confirmation, programme scheduling, season card in Γύρω μου and the public box page.

### P3-M6 · PT squads (A + W)
- Create from `Box › Πελάτες μου`, invite clients, squad channel, membership follows coaching.

### P3-M7 · Partners (A + W)
- Opt-in profile per club, swipe deck with filters, mutual match, Partners messages tab, «Κλείστε
  μαζί» booking suggestion, report/block, Ρυθμίσεις opt-out.

### P3-M8 · Solo-coach tier (A + W)
- Organization kind and tier, coach onboarding, coach-centred Box, session packages, «Team» club and
  open bootcamps, pricing config.

### P3-M9 · Native wrapper (A + W + mobile)
- Capacitor project, build scripts for iOS and Android, deep links, native push, capability flags;
  store submission is an owner action.

### P3-M10 · Apple Health and Health Connect (A + mobile)
- Permissions flow from `Εγώ › Συνδεδεμένες συσκευές`, ingest, dedupe, status row.

### P3-M11 · Widgets, geofence and NFC (A + mobile)
- Three widgets, geofenced check-in reminder, NFC door tags in the check-in desk settings.

### P3-M12 · AI scaling suggestions (A + W)
- ScalingAdvisor port and adapter, coach approval queue, approved suggestions as modifications,
  metering, off by default.

### P3-M13 · Voice logging (A + W)
- Record button in `Νέα καταχώρηση`, transcription, parsed draft, confirm to save.

**How each milestone runs:** same as Phase 2. Backend first (data, API, OpenAPI); then a mockup
board with alternatives and the recommendation marked before any screen; outcome recorded in §5a;
then the web side. Tests first where practical; full API, web and Playwright suites at the end of
every milestone; all copy in the 12 locales.

## 5a. UX decisions (filled in per screen, from the boards)

### WOD goals (2026-10-21, [board 18](https://claude.ai/artifact/4FpEmCjYhx3NXDUmuPqqbw))
All recommended options, with every recommended extra.
1. **Coach (Q1 A):** a «Στόχοι» panel in the workout editor, filled from the exercises as the coach types; edits stick,
   «Επαναφορά πρότασης» restores the suggestion; the toggle «Εμφάνιση στόχων στα μέλη» sits at the top. Extras: a gym
   setting «Στόχοι ορατοί από προεπιλογή» sets the toggle's starting value (off by default); class variants and scaled
   versions inherit the goals and the coach can change them per variant.
2. **Picking (Q2 A + note «Both tap and list search»):** one picker with the rotatable 3D body (tap group, tap again for
   the head, long press cycles the role) and a searchable list by region, sharing one selection. Picking a head zooms
   onto it.
3. **Member card (Q3 A):** compact strip in the workout card (small figure, top muscles, qualities, stimulus); tap opens
   the 3D sheet. Members see κύριοι and βοηθητικοί on the card, σταθεροποίηση only in the sheet. The strip also shows
   on the «Έτοιμος;» screen before the timer.
4. **«Τι ένιωσες;» (Q4 A):** one optional step after timed and logged workouts: goal chips tap to «felt», «+ Κάτι άλλο»
   from the body, qualities, «Παράλειψη». Workouts without goals still offer the step from the body (can be switched
   off in Ρυθμίσεις); the journal entry shows «Ένιωσα: …» with the entry's visibility.
5. **Stimulus (Q5 A):** free text with tap-to-insert phrases.
6. **Coach view (Q6 A):** totals on the workout and the class from shared entries only, shown only with 3 or more
   entries; also lists goals nobody felt.

### Anatomy atlas (2026-10-21, ADR-164)
No board; decided for least clutter (owner's standing instruction), full list in ADR-164 «Decisions».
1. **Home:** `/journal/atlas` under the Πρόοδος tab, `?node=` deep link (`atlasHref`); P3-M3's Μυϊκή κάλυψη links there.
2. **One screen:** figure (front and back), breadcrumb Σώμα › Περιοχή › Ομάδα › Κεφαλή, node panel; segmented
   «Εξερεύνηση | Η κάλυψή μου»; range chips 1 / 4 / 12 εβδ. (4 default).
3. **Counting:** primary 1 set, secondary ½, stabilizer 0, once per node; unknown set count = 1; levels by sets per
   week (low > 0, medium ≥ 3, high ≥ 8), labelled as an indication, not a target.
4. **Heat map:** groups by level; heads only inside the selected group.
5. **Panel:** what it does (one sentence, i18n), your sets with level and per week, «Κυρίως από» top 3, felt count
   when > 0, gym exercises (first 5, «Όλες (n)») with on-demand videos matched by tag/title behind the package gate.
6. **Entry from goals:** «Άτλαντας ›» in the goals sheet and tappable muscle chips; the strip is unchanged.

### Native wrapper (2026-10-21, ADR-171, no board: owner's standing instruction)
1. **Shell:** Capacitor 8 in `apps/mobile`, app id `app.milos.member`, «Milos»; the app loads the deployed web app
   (production `https://milos.4kq.net`, or `MILOS_APP_URL`), so web and apps ship together. Other hosts open in the
   system browser (allow-list: the app host and `connect.garmin.com`). A local «Χωρίς σύνδεση» page covers a cold start
   offline; after that the outbox and service worker behave as on the web.
2. **Share links open the app:** `/c/`, `/join/`, `/b/`, `/r/`, `/events/`, `/trials/`, `/buddy/` through universal
   links and App Links; `/.well-known` files come from env and answer 404 until the store ids exist.
3. **Push:** the bell and profile switches use the OS push inside the app (APNs on iOS, FCM on Android), web push in a
   browser; tapping a push opens its page. Off until the owner adds the keys.
4. **No new screens, no clutter:** no install prompt (none exists on the web); in the app «Συνδεδεμένες συσκευές» shows
   only this phone's health row, as «Σύντομα» until P3-M10; the web keeps both rows as «Με την εφαρμογή». The page draws
   under the notch with safe-area padding, unchanged in browsers.
5. **Owner actions:** Apple developer account and team id, APNs key, Firebase project and `google-services.json`, Play
   Console and signing keys (fingerprints), icons and store listings (ADR-171 «Owner actions»).

## 6. Ethics and safety checklist (brief §8.6)
- [ ] Insights labelled as indicators, never medical advice; none before enough data
- [ ] Training load shown as an overload indicator, never a verdict
- [ ] Partners: club-verified only, mutual consent, report/block, optional gender preference, «training partner» copy
- [ ] Partners hidden unless the member opts in, per club
- [ ] AI suggestions never reach an athlete without coach approval
- [ ] Voice recordings deleted after transcription
- [ ] Phone health data follows D8/D11 of Phase 2 (consent, delete, export)

## 7. Open questions
1. Brief §10 Q2: prices for gym tiers and the solo-coach tier (ANR).
2. Brief §10 Q6: when to start the wrapper; Apple and Google developer accounts are owner actions.
3. ~~Atlas asset licence~~ Decided: anatomy-models (D2).
4. Should seasons support card payment later, and through which processor?

## 8. Progress
- [x] Step 1 explore · [x] Step 2 decisions · [x] Step 3 plan
- [x] P3-M1 (ADR-163) · [x] P3-M2 (ADR-164) · [ ] P3-M3 · [ ] P3-M4 · [ ] P3-M5 · [ ] P3-M6 · [ ] P3-M7
- [ ] P3-M8 · [x] P3-M9 (ADR-171) · [ ] P3-M10 · [ ] P3-M11 · [ ] P3-M12 · [ ] P3-M13
