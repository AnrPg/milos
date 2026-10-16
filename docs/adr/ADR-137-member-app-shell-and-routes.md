# ADR-137: Member app shell, four tabs and route moves
Date: 2026-10-15
Status: Accepted

## Context
Redesign Phase 1 (`docs/plans/redesign-phase-1-member-app.md`) turns the
member app into four fixed tabs: Αρχική, Box, Ημερολόγιο and Εγώ. Before
this, members navigated a top bar of up to nine links (Training, Schedule,
Journal, Progress, Coaching, Videos, Appointments, Wellbeing, Reviews) whose
pages lived at unrelated top-level URLs, and secondary links sat in a "More"
drawer. The brief asks for stable screens, one home per object and nothing
lost from today's features.

## Decision
1. **Four tabs, one bottom bar.** `clientNavItems()` in
   `lib/role-navigation.ts` returns exactly four tabs. Each tab claims its
   pages by path prefix: Αρχική `/` (exact), `/feed`, `/clubs`; Box `/box`,
   `/class-timer`, `/workouts`; Ημερολόγιο `/journal`; Εγώ `/me`.
   `components/nav/BottomTabBar.tsx` renders them for members and athletes
   (not admins, not without a membership). `showsBottomBar()` hides it on
   full-screen surfaces: workout execution, free-text execution and the
   class-timer display and control pages. `TopNav` keeps brand and org
   selection but no longer renders member links.
2. **Pages move under their tab, old URLs redirect (D3).**
   `lib/member-routes.ts` holds `MEMBER_ROUTE_MOVES` (most specific first):

   | Old | New |
   |---|---|
   | `/my-workouts/history` | `/journal` |
   | `/journal` (vault) | `/journal/vault` |
   | `/my-workouts/pantheon` | `/journal/pantheon` |
   | `/my-workouts` | `/box/workouts` |
   | `/schedule`, `/appointments`, `/videos` | `/box/…` |
   | `/coaching` | `/box/coach` |
   | `/progress`, `/wellbeing`, `/reviews` | `/journal/…` |
   | `/profile` | `/me/settings` |
   | `/account/billing` | `/me/payments` |
   | `/account/activity/*` | `/me/activity/*` |

   `next.config.ts` turns the table into 307 redirects, with and without the
   `/org/:slug` prefix, keeping the query string. Notification payloads
   stored before the move carry old URLs, so `notification-links.ts` maps
   them through `currentMemberPath()` on the client. Workout execution,
   class timer and `/workouts/*` do not move.
3. **Hubs are fixed pages.** `/box`, `/journal` and `/me` render hub
   components (`components/member-app/*`) whose cards keep their place with
   an empty state, so the screen never reflows. Box shows today's training
   (class WOD, the member's own version of it, then coach programmes as
   source chips), Καταγραφή (the existing training-log dialog) and Έναρξη ▶
   (the existing execution route via `useWorkoutLauncher`), the next
   booking, an action row gated by entitlement and the membership card.
   Ημερολόγιο has one write action, Νέα καταχώρηση, listing only entry
   kinds that exist and opening the flow that already owns each. Εγώ is a
   fixed list of every secondary link, so there is no "More" drawer.
4. **No rollout flag (D2).** The redesign branch replaces the member
   navigation outright and ships with `v2.0.0`.
5. **Staff in "My training" view (D5)** get the same four tabs; Εγώ ›
   Διαχείριση switches back to the console.

## Rationale
- Prefix ownership in one place lets every page, including later ones
  (`/clubs`, `/feed`), light the right tab without per-page code.
- One route table drives redirects, notification mapping and tests, so the
  three cannot drift apart.
- 307 keeps the redirects reversible while the app is unreleased; they can
  become permanent once `v2.0.0` has been out long enough.
- Reusing the existing dialogs and routes (training log, execution, PR form,
  wellbeing, reviews) means the hubs add no second write path for any object.

## Alternatives Considered
- **Keep URLs, change only the navigation.** Cheaper, but leaves pages whose
  URL contradicts their tab and makes Phase 2 pages harder to place.
- **A feature flag for the new shell.** Rejected by the owner: the app is not
  released, so a flag would only add a second navigation to maintain.
- **Server-side today aggregation now.** Better long term (one request,
  testable in Elixir), but the API toolchain is not available in this
  session; the web aggregation is a pure, tested function that the server
  endpoint can replace (TD-104).

## Consequences
- Members see the four tabs on every page except full-screen execution.
- Every internal link was moved to the new paths; the redirects only catch
  bookmarks, old notifications and external links.
- Box's today card makes four requests (schedule, assignments, executions,
  training-log sources) where a single endpoint would do (TD-104).

## Implementation Notes
- The Journal hub's Ροή is the former history page; the former `/journal`
  (vault) moved to `/journal/vault`.
- The 1.4k-line member landing (`landing-page.tsx`) was split by owner and
  deleted. Αρχική (`HomeHub`) keeps greeting and quote, the gym's WOD of the
  day, challenges, the opt-in leaderboard (now a full card, which also ends
  the 360 px popover overflow of TD-103 (4)) and an empty club-posts slot that
  ADR-138 fills. Πρόοδος is no longer package-gated: streak, badges and
  scores, Pantheon and the history export are for everyone; only the detailed
  statistics stay behind `view_advanced_analytics`, and `/journal/pantheon`
  lights the Πρόοδος segment. Ροή merges finished executions and training-log
  entries per day (`journal-flow.ts`; ADR-118 keeps them disjoint) and keeps
  "Share in Milos" from the old landing. The landing's "Log workout" pill
  (`workout-cta.ts`) is replaced by Box's today card.
- `MembershipEntitlement.tsx` was extracted from the billing page so Box and
  Πληρωμές share one entitlement card; `TrainingLogDialog` and
  `useWorkoutLauncher` were extracted for the same reason.
- Εγώ › Κοινοποίηση & ορατότητα (`/me/sharing`) gathers PR sharing, the
  leaderboard opt-in and weekly rest days. Ρυθμίσεις keeps language,
  security, personal info and avatar; its Vault tab, training history and
  review list moved to Ημερολόγιο (`/journal/vault`, `/journal/reviews`), so
  each exists once. Old `#vault`, `#history`, `#pr-sharing`,
  `#training-schedule` and `#account-activity` anchors redirect on the client.
  The rest-day picker now allows the five days the API accepts (it stopped
  at three).
- Following the feature map, Ημερολόγιο's segments are Ροή · Vault · Ευεξία
  · Πρόοδος. Reviews have no segment: `journal-flow.ts` files them in Ροή by
  the day they were written, and `/journal/reviews` (the review form) lights
  Ροή. Νέα καταχώρηση groups its kinds as Προπόνηση · Ευεξία · Coach and
  hides a group with no kinds, so kinds can be added without moving others.
