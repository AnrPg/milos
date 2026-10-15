# Redesign Phase 1: the member app as Feed · Box · Ημερολόγιο · Εγώ

Date: 2026-10-15
Branch: `redesign/social-centered` (baseline release `v1.0.0` = `main@ee6f189`; the redesign ships as `v2.0.0`)
Source of truth: `docs/product/2026-10-15-milos-product-vision-and-ia.md` (the brief) and
`docs/product/mockups/milos-ia-mockup.html` (screens in `docs/product/mockups/screens/`).
`milos-bottom-bar-exploration.html` is superseded and is not a spec.

> Naming: the brief's roadmap rows "v1/v2/v3" are **Phase 1/2/3** of the redesign. `v1.0.0`/`v2.0.0`
> are release tags.

## 1. Goal

Re-home every existing member capability into the four fixed tabs of brief §6.1, make the Feed the
landing screen, and give each gym one closed club with its automatic channels, so that the Phase 1
pitch holds: "Τα μέλη σου μένουν γιατί είναι κοινότητα."

### In scope (brief §9, Phase 1 row)
- Fixed bottom bar with 4 tabs for members and athletes (§6.1), Feed as landing.
- **Box** hub: today's workout card (`Καταγραφή` / `Έναρξη ▶` into the unchanged execution screen),
  injury warning, next booking, action row (Πρόγραμμα · Ραντεβού · Βίντεο · Coach), membership card,
  announcements (§7.4, mockup 08).
- **Ημερολόγιο** hub: `Νέα καταχώρηση` sheet (existing entry types only), segments
  Ροή · Vault · Πρόοδος (+ Ευεξία for the existing injury/readiness data), visibility badge on every entry
  (§7.7, mockups 15–18, 23).
- **Εγώ** hub: profile header + tabs (Αναρτήσεις · PRs · Clubs) and the fixed settings list, each row
  linking to the existing page that owns it (§7.11, mockups 24–33 where the feature exists).
- **One closed club per gym** with auto channels `#ανακοινώσεις`, `#wod-σήμερα` (+ leaderboard),
  `#challenges`, and class-slot groups (§7.1 governance table), posts with origin label, `⊕` compose
  with audience club›channel, optional workout attachment (mockups 01–03).
- Visibility ladder for journal entries (§7.7, §8.2).
- Feature-coverage: nothing a member can do today loses its access point (§8.1, mockup «Κάλυψη»).

### Non-goals (Phase 2/3, do not build; do not block)
- Phase 2: open clubs, events, `Γύρω μου` + filters + saved filters, public box page, trial-slot policy,
  member groups with approval, QR rotating check-in + Wallet, member referral UI, Σώμα (snapshots,
  photos), Ευεξία tracking (water, sleep, meals, cravings, buddy), Garmin, cross-org unified journal,
  followers/public audiences.
- Phase 3: Partners/swipe, seasons, WOD goals + anatomy atlas, advanced analytics views, PT squads,
  solo-coach tier, native wrapper, AI coach assistant.
- The `Γύρω μου` scope toggle renders but is disabled with a "σύντομα" empty state; the Ευεξία and Σώμα
  segments are hidden until Phase 2 (stable-screen rule: no half-empty segment).
- The workout execution screen (`/workouts/[id]/execute`, `/workouts/free-text/execute`) does not change.
- Staff/admin web console does not change; `Box › Πελάτες μου` for coaches is Phase 1 stretch
  (milestone M9), otherwise Phase 2.

## 2. What exists today (Step 1 findings)

### Web (`apps/web`)
- Shell: `app/layout.tsx` renders `TopNav` (desktop priority nav + mobile menu, notification bell,
  messages panel, org selector, profile menu) and `SectionTabs` for the page group.
- Member nav: `lib/role-navigation.ts` → `clientNavItems` = Home `/` · Training (`/my-workouts` or
  `/schedule`, plus `/appointments`, `/videos`) · Journal (`/journal`, `/my-workouts/history`,
  `/my-workouts/pantheon`, `/progress`, `/coaching`, `/wellbeing`). `sectionGroupFor` gives Training
  4 tabs and Journal 6 tabs (the brief says "~10"; it is 6 plus the gated ones).
- Tenant routing: `/org/:slug/*` is rewritten to `/*` (`next.config.ts`); the active org comes from
  the URL, then localStorage (`lib/organization-slug.ts`).
- Landing: `components/landing-page.tsx` (1.4k lines): member hero (streak, badges), Motivation /
  Perseverance / Volume stats, seasonal challenges, opt-in leaderboard, recent completions with
  history export and "Κοινοποίηση στο Milos".
- Package-gated features: `components/client/entitlement.ts` (`videos`, `progress`, `coaching`,
  `appointments`).
- i18n: `next-intl`, 12 locales in `apps/web/messages/*.json`; `npm run i18n:check` fails on missing
  keys, untranslated English prose, and hard-coded UI copy. Every new string needs all 12 locales.
- Realtime: Phoenix Channels via `lib/realtime.ts`; offline outbox in `lib/offline-command-outbox.ts`
  and `components/outbox/*`.
- Design tokens: `app/globals.css` (`--bg`, `--panel`, `--border`, `--primary`, …), themes in `lib/theme.ts`.

### API (`apps/api`)
- Hexagonal + bounded contexts (AGENTS.md rules 1–7). Contexts include `Messaging`
  (threads: `direct | assignment | class_slot`), `Gamification` (global leaderboard opt-in, seasonal
  challenges + challenge leaderboard), `Execution` (`training_log_entries`, `workout_executions`, vault),
  `Pantheon` (PRs, `coach_visibility` boolean per user), `Feedback` (reviews, `admin_only|user_visible`),
  `Wellbeing` (injuries, `admin_only|user_and_admin`), `Coaching` (relationships, notes, reply alerts,
  form reviews), `Organizations` (`organization_settings.settings` free-form map).
- Membership JSON (`/api/memberships`) exposes only `brand_name`, `brand_logo_url`,
  `brand_primary_color` from settings.
- Contract-first: OpenAPI via `open_api_spex`; `npm run generate:api` runs `mix milos.export_openapi`.
- Last ADR: ADR-136. Last tech-debt id: TD-103.

### §8.1 table check: mismatches
| Brief claim | Reality | Consequence |
|---|---|---|
| Member nav "Journal with ~10 sub-tabs" | 6 tabs (Finished, History, Pantheon, Progress†, Coaching†, Wellbeing; † package-gated) | Cosmetic; coverage list below uses the real set |
| `#wod-σήμερα` + leaderboard reuses existing leaderboards | Only a **global** streak/score leaderboard (landing) and **per-challenge** leaderboards exist; there is no per-class/per-WOD score leaderboard | New query over `training_log_entries.section_scores` for today's class WOD (M6) |
| "Shared PRs → Εγώ › PRs" | PR sharing grants exist (ADR-129/132) but there is no "my posts" concept | Εγώ › PRs lists shared PRs; Αναρτήσεις grid arrives with posts (M7) |
| Not in the table: `/reviews`, `/account/billing`, `/account/activity/chats`, `/join/[slug]` | Exist as member pages | Homes: Ημερολόγιο › Νέα καταχώρηση › Αξιολόγηση (+ list in Ροή); Εγώ › Πληρωμές; Αρχική ✈; Εγώ › Τα box μου |
| Visibility enum "today: PR coach visibility, reviews, injuries" | Three unrelated flags; training-log notes have no visibility | ADR-139 + M5 |
| Class timer display "becomes a Box card while running" | `/class-timer/[slotId]/display` exists, driven by `useClassTimer` | Box next-class card links to it while a timer is live (M3) |

## 3. Decisions

Asked on decision cards on 2026-10-15; work proceeds on the recommended option unless the answer differs.

| # | Decision | Default taken | ADR |
|---|---|---|---|
| D1 | Where clubs/channels/posts live | **Chosen 2026-10-15:** new `Community` bounded context (Club, Channel, ClubMembership, Post); Messaging keeps DMs + coach inbox | ADR-138 |
| D2 | Rollout | **Chosen 2026-10-15:** everyone at once. The redesign branch replaces the old member navigation outright; no flag | ADR-137 |
| D3 | URLs | **Chosen 2026-10-15:** move and redirect. Member pages move under `/box/*`, `/journal/*`, `/me/*`; old URLs redirect (`lib/member-routes.ts` + `next.config.ts`), and legacy notification payload URLs are mapped client-side | ADR-137 |
| D4 | Visibility storage | **Chosen 2026-10-15:** migrate everything. One `visibility` column on every entry type (training-log entries, reviews, injuries, PRs, coaching notes from the athlete), with a backfill migration from the old flags | ADR-139 |
| D5 | Staff in "My training" view | Same 4 tabs; `Εγώ › Διαχείριση` links to the console | ADR-137 |
| D6 | `#wod-σήμερα` leaderboard | Scores = today's class-WOD log entries of members who opted in to leaderboards (existing opt-in), ranked by the WOD's score type | ADR-138 |
| D7 | Class-slot groups | Auto-created per recurring `class_series`; membership suggested to members with ≥3 bookings of that series in 4 weeks (brief §10 Q3 left open; 3 is the default) | ADR-138 |
| D8 | Moderation in Phase 1 | Staff can hide/delete any post; authors delete their own; report → staff queue is Phase 2 (brief §10 Q4) | ADR-138 |
| D9 | Media on posts | Text + optional workout attachment only; photo upload is Phase 2 (needs storage/GDPR decisions) | ADR-138 |

## 4. Architecture

### ADR-137 Member app shell and routes
- Route moves (D3): `/my-workouts`→`/box/workouts`, `/schedule`→`/box/schedule`, `/appointments`→`/box/appointments`,
  `/videos`→`/box/videos`, `/coaching`→`/box/coach`, `/my-workouts/history`→`/journal`, old `/journal`→`/journal/vault`,
  `/my-workouts/pantheon`→`/journal/pantheon`, `/progress`→`/journal/progress`, `/wellbeing`→`/journal/wellbeing`,
  `/reviews`→`/journal/reviews`, `/profile`→`/me/settings`, `/account/billing`→`/me/payments`,
  `/account/activity/*`→`/me/activity/*`. Execution, class-timer and `/workouts` stay.
- No rollout flag (D2): the branch ships the new shell to every member when `v2.0.0` is released.
- `lib/role-navigation.ts`: `clientNavItems()` returns the 4 tabs with `match` prefixes that claim the
  old pages: Box ← `/box`, `/my-workouts` (not history/pantheon), `/schedule`, `/appointments`,
  `/videos`, `/coaching`, `/class-timer`; Ημερολόγιο ← `/journal`, `/my-workouts/history`,
  `/my-workouts/pantheon`, `/progress`, `/wellbeing`, `/reviews`; Εγώ ← `/me`, `/profile`, `/account`;
  Αρχική ← `/` (exact), `/feed`, `/clubs`.
- `components/nav/BottomTabBar.tsx`: fixed bottom bar (safe-area inset), icons + labels, active by
  longest prefix; rendered by the layout for client surfaces. `TopNav` drops its primary
  links for members and keeps brand/org selector only on hubs that need it.
- Execution and class-timer display routes hide the bar (full-screen).

### ADR-138 Community context
Tables (one migration each, in dependency order):
- `community_clubs(id, organization_id, kind enum[gym, open, member_group, pt_squad, season] — only gym used, name, slug, join_policy enum[members_only, open, approval] — only members_only used, archived_at)`; unique `(organization_id) where kind = 'gym'`.
- `community_channels(id, club_id, kind enum[announcements, wod, challenges, class_slot, season, custom], name, write_policy enum[staff, members, participants, system_and_members], context_type, context_id, archived_at)`; unique `(club_id, kind) where kind in (announcements, wod, challenges)`, unique `(club_id, context_id) where kind = 'class_slot'`.
- `community_club_memberships(id, club_id, user_id, role enum[member, staff], notify_level enum[all, mentions, none])`.
- `community_channel_memberships(id, channel_id, user_id, source enum[auto, opt_in, suggested])` for opt-in channels.
- `community_posts(id, organization_id, club_id, channel_id, author_id, audience enum[club_channel, followers, public] — only club_channel used, body, attachment_type enum[training_log_entry, pr, workout], attachment_id, hidden_at, hidden_by_id, deleted_at, inserted_at)`.
- `community_post_reactions(post_id, user_id, kind)` and `community_post_comments(id, post_id, author_id, body, deleted_at)`.
Provisioning: `Application.ProvisionGymClub` runs on organization provisioning and by a backfill
Oban job for existing orgs; membership sync subscribes to the existing membership PubSub events.
Feed query: `Community.Queries.Feed` (posts from the user's clubs, newest first, cursor pagination);
`#wod-σήμερα` card and leaderboard via `Application.GetWodTodayCard` (Scheduling + Execution + Gamification
public APIs). Realtime: `community:club:<id>` topic for new posts.

### ADR-139 Journal visibility ladder
- Enum `private | coach_can_view | coach_reply_requested | rated | posted` (Ecto.Enum, room for later).
- Migrations add a `visibility` column (same enum) to `training_log_entries`, `feedback_reviews`,
  `wellbeing_injury_reports` and PR records, then backfill from the old flags: PR → `coach_can_view`
  when the owner's `coach_visibility` is on, else `private`; review → `rated` (its `admin_only`/
  `user_visible` stays as the audience of the rating); injury → `coach_can_view` (always visible to
  coaches, brief §4.5); log entry with a reply alert → `coach_reply_requested`, else `private`.
  Old columns stay until a later cleanup migration (non-destructive; TD entry).
- Read model `Application.GetJournalFeed` returns entries of all kinds with their stored `visibility`.
- Coach reads of sensitive entries reuse the coach-note read audit pattern.

## 5. Milestones (each one PR into `redesign/social-centered`)

Legend: **W** = web only (testable in cloud), **A** = needs the Elixir toolchain (see §8).

### M1 · Bottom bar and tab mapping (W)
- Files: `lib/role-navigation.ts` (`clientNavItems` → 4 tabs, +tests),
  `components/nav/BottomTabBar.tsx`, `components/TopNav.tsx`, `app/layout.tsx`, `messages/*.json`.
- Accept: members/athletes see 4 tabs on every page except execution/class-timer display;
  the right tab is active on every legacy route (§6.1, mockups 01/08/16/24).
- Tests: tab-ownership table test over every legacy member route.
- Verify: `npm run lint && npm run type-check && npm test && npm run i18n:check`.

### M2 · Hubs as stable pages (W)
- `/box`, `/me` routes; `/journal` becomes the hub; `/` renders the Feed hub for members (fixed slots +
  empty states); the old landing content moves to Ημερολόγιο › Πρόοδος (M4). Admins keep `/admin`.
- Accept: each hub has fixed card order with empty states (§4.2, §8.5); every row links to an existing page.

### M3 · Box hub content (W)
- Today's workout card from existing assigned-workout + schedule APIs with source chips; `Καταγραφή`
  opens the existing training-log form; `Έναρξη ▶` → existing execute route; injury warning via
  `InjuryWarnings`; next booking (cancel, check-in), class-timer link while live; action row gated by
  entitlement; membership card from `/me/finance`.
- Accept: mockup 08; nothing from Training tabs lost.

### M4 · Journal hub (W)
- `Νέα καταχώρηση` sheet listing existing entry types (Προπόνηση, PR, Τραυματισμός/Πώς νιώθω via
  wellbeing, Βίντεο τεχνικής if entitled, Αξιολόγηση, Σημείωση) that open existing forms; segments
  Ροή (history + finished), Vault, Πρόοδος (progress + Pantheon), Ευεξία (existing wellbeing).
- Accept: mockups 15–17; visibility badge renders from derived visibility (client-side mapping until M5).

### M5 · Visibility ladder (A)
- Migrations + backfill on every entry type, schemas, `GetJournalFeed`, OpenAPI, generated client,
  badge from server; set visibility on each entry type; tests for every backfill mapping.

### M6 · Community context: clubs and channels (A)
- Migrations, schemas, commands/queries, `ProvisionGymClub`, backfill job, membership sync, OpenAPI,
  controller; Εγώ › Clubs lists the gym club.

### M7 · Posts, feed and compose (A + W)
- Post/comment/reaction commands, feed query, realtime topic; `⊕` compose sheet with audience
  club›channel and workout attachment; Feed with club bar and origin labels; Εγώ › Αναρτήσεις grid.

### M8 · Auto channels content (A + W)
- `#ανακοινώσεις` (staff write; Box announcements card reads it), `#wod-σήμερα` card + leaderboard (D6),
  `#challenges` (existing challenges), class-slot groups (D7).

### M9 · Εγώ settings (W)
- Εγώ › Κοινοποίηση & ορατότητα
  (PR sharing, gamification prefs), Ρυθμίσεις (language, theme, outbox status), Βοήθεια (tours),
  Διαχείριση for staff. Stretch: Box › Πελάτες μου for coaches.

## 6. Feature-coverage checklist (brief §8.1, mockup «Κάλυψη»)
- [x] Messages (direct, threads, search) → Αρχική ✈; Box › Coach filtered (M2/M3)
- [x] Notifications, web push → Αρχική ♡ (M2)
- [ ] Seasonal challenges + opt-in leaderboard → Club #challenges (M8); own progress → Πρόοδος (M4)
- [ ] Global leaderboard opt-in → Εγώ › Κοινοποίηση & ορατότητα (M9)
- [ ] "Κοινοποίηση στο Milos" → ⊕ with attachment (M7); until then, kept in Vault/Ροή (M4)
- [x] Shared-with-me PRs → Ημερολόγιο › Πρόοδος › Pantheon (M4)
- [x] WOD of the day, scale levels → Box card (M3)
- [x] Execution (timer, steps, modifications, notes) → Box › Έναρξη, Vault › Επανάληψη (M3/M4)
- [x] Injury warnings + acknowledge → Box card (M3)
- [x] Schedule, booking, waitlist, cancel, guest pass, locations, ICS → Box › Πρόγραμμα (`/box/schedule`) (M3)
- [ ] Class and open-gym check-in → Box next-booking card (M3)
- [ ] Class timer display → Box next-class card while live (M3)
- [ ] Assigned workouts: reject, reschedule, request → Box › Coach / workout card chip (M3)
- [x] Appointments → Box › Ραντεβού (M3)
- [x] Videos → Box › Βίντεο (M3)
- [x] Form reviews, nutrition plan → Box › Coach (`/coaching`) (M3); Νέα καταχώρηση › Βίντεο τεχνικής (M4)
- [x] Entitlement, corporate enrollment → Box › Συνδρομή (M3)
- [x] Invoices, refund receipts (`/account/billing`) → Εγώ › Πληρωμές (M2)
- [x] Training log (class, assigned, library, free), RPE, scores, void → Ημερολόγιο + Box › Καταγραφή (M3/M4)
- [ ] Log notes and execution notes → Ροή (M4), visibility (M5)
- [x] Reviews (`/reviews`) → Νέα καταχώρηση › Αξιολόγηση (M4)
- [x] Wellbeing: injuries, readiness → Ημερολόγιο › Ευεξία (M4)
- [x] Vault + repeat → Ημερολόγιο › Vault (M4)
- [x] History, finished workouts → Ροή (M4)
- [x] Pantheon (PRs, history, correction, share text) → Πρόοδος (M4)
- [x] Progress stats (Motivation, Perseverance, Volume, streak) from landing → Πρόοδος (M4)
- [x] History export → Πρόοδος (M4)
- [ ] Profile, avatar, language, theme → Εγώ (M2/M9)
- [ ] PR sharing grants, coach visibility → Εγώ › Κοινοποίηση & ορατότητα (M9)
- [ ] Gamification preferences → Εγώ › Κοινοποίηση & ορατότητα (M9)
- [ ] Org memberships, join link (`/join/[slug]`), invitations → Εγώ › Τα box και τα clubs μου (M2)
- [x] Chats activity (`/account/activity/chats`) → Αρχική ✈ (M2)
- [ ] Offline outbox status → Εγώ › Ρυθμίσεις (M9); global panel stays
- [ ] Onboarding/tours → Εγώ › Βοήθεια (M9)
- [x] Staff: console → Εγώ › Διαχείριση (M2)

## 7. Open questions
1. Brief §10 Q3: how many bookings make a member "frequent" for class-slot groups (default 3 in 4 weeks).
2. Brief §10 Q4: moderation minimum for Phase 1 (default: hide/delete, no report queue).
3. Should `#wod-σήμερα` show members who did not opt in to leaderboards as "Εσύ" only (default yes,
   others hidden)?

## 8. Environment notes
- The cloud session cannot reach `repo.hex.pm` or `builds.hex.pm`, so `mix` deps and an OTP 27 build
  cannot be installed here. **A** milestones need either those hosts allowed in the cloud environment's
  network settings, or a Remote Control session on a machine with the Docker stack.
- Pushes from the cloud session are limited to the session branch; milestone PRs go from that branch
  into `redesign/social-centered`.

## 9. Progress
- [x] Step 1 explore
- [x] Step 2 decisions (cards posted; defaults recorded in §3)
- [x] Step 3 plan (this file)
- [x] M1 · [x] M2 (Αρχική hub with fixed slots; posts slot empty until M7) · [x] M3 (class-timer link and check-in: TD-105) · [x] M4 (old landing split into Αρχική, Ροή and Πρόοδος and deleted) · [ ] M5 · [ ] M6 · [ ] M7 · [ ] M8 · [ ] M9
