# ADR-196: One inbox, the fixed Εγώ list, and a home for every sharing choice
Date: 2026-10-24
Status: Accepted

## Context
The vision (§4, §6.3, §7.10, §7.11) gives messages one home (Αρχική › ✈, filtered from Box › Coach) and Εγώ a fixed list. The code had drifted from it:
- Chats lived in three places: the ✈ drawer, Εγώ › Συνομιλίες (`/me/activity/chats`) and, after ADR-193, `/me/messages`.
- Εγώ › PRs showed every PR, even private ones.
- Εγώ carried extra rows: interests, body settings, business, box switcher, tour, checklist, console and coach practice.
- Units and journal sections were only in Σώμα › Ρυθμίσεις, and rest days were under Κοινοποίηση.
- Several push links pointed at routes that no longer exist and returned 404.

## Decision
1. **One inbox at `/messages`.**
   - Segments: Όλα · Coach · Clubs · Partners. The filter is in the URL (`?filter=coach`, `?thread=`, `?folder=requests`), and `/messages/[id]` opens a person conversation.
   - Each kind of thread is an `InboxSource` (`components/chat/inbox/inbox-sections.tsx`), so new kinds plug in without changing the list. The current sources are message requests, person conversations, box threads, partners and buddies.
   - Gym threads are filed by `threadSegment`. Assignment threads, threads with a coach, and threads that hold a coaching message file under Coach; box and class threads file under Clubs.
   - The ✈ count adds person conversations and requests to the gym threads.
   - Old paths redirect: `/me/messages`, `/me/activity/chats`, `/account/activity/chats` and `/partners`.
2. **PRs on the profile are chosen one by one.**
   - New field `user_pr_records.profile_audience`, either `private` (the default) or `followers`.
   - A follower read policy guards it.
   - New endpoints: `PUT /api/prs/:id/profile-audience` and `GET /api/prs/profile/:user_id`.
   - Εγώ › PRs shows only the chosen PRs and says how many others are private. A person's profile shows profile PRs plus ADR-129 grants.
3. **Sharing opt-ins are stored settings.**
   - Two new gamification preferences: `pr_celebrations` (off until the member opts in) and `challenge_rankings` (on unless the member opts out). Challenge leaderboards leave out anyone who opted out, through the definer `palee_hides_challenge_rankings`.
   - New endpoint `GET/PUT /api/me/journal/visibility-defaults` sets the starting rung for new workouts, notes and check-ins.
4. **Κοινοποίηση & ορατότητα is grouped the way the mockup groups it**, in this order:
   - Ο coach μου βλέπει: PRs, the wellness summary and measurements. Injuries are always visible.
   - Κοινότητα: leaderboard, PR celebrations, challenges and Partners.
   - PRs on my profile.
   - PRs shared with accounts.
   - Default for new entries.
   - Then the account, people-search and blocking switches.
5. **Εγώ is the fixed §7.11 list.** Rows that left Εγώ moved here:

   | What moved | Where it lives now |
   |---|---|
   | Interests, body settings, business, units, journal sections, rest days | Ρυθμίσεις |
   | The box switcher | Τα box και τα clubs μου |
   | Tour, first steps, how visibility works, contact the box, report a problem, coach practice, staff extras, password resets | `/me/help` (Βοήθεια & ξενάγηση) |

   The count of password resets waiting stays on the Help row.

   *Amended 2026-10-24:* the staff console switch («Διαχείριση») is the last row of Εγώ itself, as in the §6.2 tree, shown to anyone with a staff role at any provider (`useOpenConsole`). Inside Βοήθεια it was too hard to find the way back from the social app.
6. **Push and notification links open current routes.** Old forms still redirect: exact moves in `MEMBER_EXACT_MOVES`, and the hash `/me/sharing#training-schedule` on the client.

## Rationale
- One home per object, and nothing lost (§4, §8.1).
- Profile PRs are opt-in per PR, because a PR on a profile is public to followers and must never appear without the member choosing it.

## Alternatives Considered
- **A single "show all my PRs" switch.** Rejected: it is too coarse, and the mockup shows a count of private PRs.
- **Keeping `/me/messages` as the inbox.** Rejected: the inbox belongs to Αρχική (§6.3), not Εγώ.

## Consequences
- Nothing posts automatic PR celebration cards yet. `pr_celebrations` is stored now so that the card, when it ships, respects the opt-in from its first day (TD-204).
- «Αναφορά προβλήματος» shows only when `NEXT_PUBLIC_SUPPORT_EMAIL` is set (TD-204).
- Existing PRs start private, so members' profiles show no PRs until they choose some.
