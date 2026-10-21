# ADR-169: Partners: training partners inside a club, mutual match, «Κλείστε μαζί»
Date: 2026-10-21
Status: Accepted

## Context
Plan §5 P3-M7 and vision §7.3 / §8.6 add Partners: swipe only among
members of the same club, verified by the gym; a mutual like opens a
conversation and a «Κλείστε μαζί 07:00» suggestion; report and block;
optional gender preference for safety; framed as a training partner, never
a date. D6 of the Phase 3 plan: opt-in per club, hidden by default; the
card shows the name, level, times and goal; no photos beyond the avatar.
The mockup puts the deck in the club page's «Μέλη» tab and the
conversations in Μηνύματα › Partners, and a «Partners · Να με προτείνει σε
μέλη» switch in Ρυθμίσεις › Κοινοποίηση & ορατότητα, off by default.

ANR's standing Phase 3 rule: no boards; pick the most robust, practical,
future-proof, modular option with the least clutter, and record it.

## Decision
1. **A Partners bounded context** (`Palee.Partners`) owns four
   tables, all tenant data of the club's gym (`organization_id` = the club's
   gym, the gym's tenant policy, purged with the gym):
   - `partner_profiles` (club, user, `active`, `level
     beginner|intermediate|advanced`, `times[]` of `early|midday|afternoon|
     evening|weekend`, `goals[]` of `strength|conditioning|weight_loss|
     skills|competition|consistency`, an optional `about` of at most 140
     characters, optional `gender woman|man|other` used only to honour
     preferences and never shown, `gender_preference any|women|men`,
     `suspended_at` when staff hid it after a report). One per club and
     person.
   - `partner_swipes` (club, swiper, target, `like|pass`). One per club and
     pair; a pass expires after 30 days so people can come back to the deck.
   - `partner_matches` (club, the pair ordered `user_a_id < user_b_id`,
     `status active|ended`, `ended_by_id`, `end_reason
     unmatched|blocked|reported|left|hidden`, read marks per side). At most
     one active match per pair in each gym (unique partial index on the gym
     and the pair; see Implementation Notes).
   - `partner_messages` (match, author, `kind text|plan`, body of at most
     2000 characters; a plan carries the class id and a snapshot of its
     name and start so it renders without Scheduling and survives changes).
2. **Eligibility is computed on every read and write** (`ClubEligibility`,
   `DeckPolicy`, `MatchPolicy`, pure): a club offers Partners when its kind
   is `gym`, `pt_squad` or `season` (membership the gym verified), or an
   `open` club whose join policy is `approval` or `invite` (staff verified
   each member); never a club anyone can walk into. The gym can switch
   Partners off (`community_settings.partners_enabled`, on by default).
   A person takes part only while they are a member of the club, their
   profile is active and not suspended, and they did not hide from members
   (`hide_from_members`). Nothing is cached: leaving the gym takes someone
   out of every deck and makes their conversations read-only at once.
3. **The deck** (`GET /api/me/clubs/:id/partners/deck`): eligible people of
   the club with an active profile, minus oneself, anyone blocked either
   way, anyone already liked, passed in the last 30 days or matched; gender
   preferences must hold both ways (a preference other than `any` excludes
   people whose gender is unset); filters `time`, `level`, `goal`. Ordered
   by what the two share (times and goals weigh 2, the same level 1, an
   adjacent level ½), then by id for a stable order; 20 cards at a time.
   Each card: nickname, avatar, level, times, goals, about and what is
   shared. No ages, no photos, no distance, no score.
4. **Swipes and matches** (`POST/DELETE /api/me/clubs/:id/partners/swipes`):
   at most 200 swipes a day per person; a like whose target already likes
   back creates the match under an advisory lock on the pair (or returns
   the pair's existing active match). Both people get one `partner_match`
   notification. Nobody ever sees who liked them before it is mutual. The
   last swipe can be undone unless it made a match. Either side ends a
   match quietly (`DELETE /api/me/partners/matches/:id`); the conversation
   stays readable and becomes read-only.
5. **Blocking is a Community capability, not a Partners one.**
   `community_user_blocks` (personal, owner-only row security, deleted
   with either account) and `Application.PeopleBlocks` block a person
   everywhere it matters: it ends every active Partners match between the
   two (`end_reason blocked`), ends any buddy link (`Buddies.end_for_block`,
   already reserved by ADR-160) and keeps both out of each other's decks.
   `palee_blocked_user_ids()` (SECURITY DEFINER) answers, for the session
   user only, whom they blocked or were blocked by. Unblocking lives in
   Ρυθμίσεις › Κοινοποίηση & ορατότητα › Αποκλεισμένα. Future features
   (direct messages, comments) can consult the same list.
6. **Reports reuse the club report queue** (ADR-143): a new target type
   `partner` (the reported person's profile in that club). Reporting also
   blocks, so the reporter never sees them again. Staff see it in the same
   queue with the profile's about line; `hide` suspends the profile (out
   of every deck of that club, its active matches in that club end with
   `hidden`), `dismiss` closes the reports. A suspended profile can't be
   switched back on by its owner.
7. **The conversation is Partners' own, not Messaging's.** Messaging
   threads are gym-scoped (the selected gym's inbox), while an open club
   joins people of different gyms; ADR-160 already chose an own,
   two-party conversation for Buddy. `GET/POST /api/me/partners/matches/
   :id/messages`, `POST …/messages/read`: newest first with an opaque
   cursor, `read_only` once the match ended or either person left the
   club. One `partner_message` push per message naming who wrote, never
   what. Live updates go to each person's `user:<id>` topic as
   `partners:changed` with ids only (as ADR-160's `buddy:changed`).
8. **«Κλείστε μαζί»** (`GET /api/me/partners/matches/:id/sessions`): for
   a match in a gym's club, the gym's classes of the next 7 days with free
   places, those either of the two already booked first, then those in the
   times both chose; for each only whether *these two* are booked, never
   who else is. Proposing (`POST …/plans`) posts a `plan` message with the
   class snapshot; the bubble opens the class sheet (`/box/schedule?
   open_slot=`) to book. Open clubs get no class list (the gym may not be
   theirs) and the chat's quick «Πάμε μαζί;» stays available.
9. **Ρυθμίσεις opt-out** (`GET/PUT /api/me/partners/settings`): the switch
   is on while any profile is active; switching it off pauses every
   profile in every club at once, switching it on resumes the paused ones
   (suspended ones stay off). Opting in the first time happens in a club.
10. **Copy** says «training partner» everywhere, offers «Ταιριάξατε» only
    as «Βρήκατε partner», and carries the safety line «Μόνο μέλη του club.
    Ταίριασμα μόνο αν το θέλετε και οι δύο.».

## Rationale
- Gym-tenant rows keep Partners inside the club's gym: purging a gym takes
  its partners data, and the club is the trust boundary the vision asks
  for. The single active match per pair avoids two parallel conversations.
- Eligibility recomputed from the membership source (Organizations for a
  gym club, club memberships otherwise) is the only way "verified, re-checked
  on every read" holds without a sync job.
- A people-level block is the future-proof shape: the safety expectation is
  "this person can't reach me", not "this person can't swipe me".
- An own conversation follows ADR-160 and works across gyms; the web reuses
  the Buddy chat's building blocks.

## Alternatives Considered
- **Messaging threads with a `partner` context type.** Rejected: threads
  live in one gym's inbox and Messaging's send path has no notion of a
  match ending; open clubs would split a pair's conversation by gym.
- **Personal (account-scoped) partner rows.** Rejected: a profile, a swipe
  and a match only mean something inside one club of one gym, and gym purge
  must remove them.
- **A match score on the card (mockup «87%»).** Rejected for clutter and
  for the dating feel; the card shows what the two share instead.
- **Distance in open clubs.** Not built: the open clubs Partners allows are
  staff-verified local clubs, and location would add a sensitive datum.

## Consequences
- `community_reports.target_type` gains `partner`; the staff queue renders
  it. `community_settings` gains `partners_enabled`.
- New notification types `partner_match`, `partner_message`.
- Buddy links end on a block through the reserved `end_for_block/3`.
- Follow-up: staff can't lift a suspension yet (a staff profile view would
  be the place); a gym-level Partners statistics card is not built.

## Implementation Notes
- **Match uniqueness is per gym, not across every club.** The rows are the
  gym's (tenant policy), so a unique index can only see one gym's rows. Two
  people who share clubs in two gyms can match once in each; the matches
  list shows both with their club name. A cross-gym index would need a
  personal table or a definer function on every insert, for a rare case.
- **Composite gym keys.** `partner_profiles`, `partner_swipes` and
  `partner_matches` reference `community_clubs(id, organization_id)` and
  `partner_messages` references `partner_matches(id, organization_id)`. The
  tenant trigger stamps the session's gym on each row; without the composite
  keys a session of gym B could write a row pointing at gym A's club. The
  RLS test asserts the constraint fires.
- **Reports name the profile.** The match carries `partner_profile_id` (the
  other person's profile in that club) so the conversation's ⋯ menu can
  report the person through the shared queue; a report also blocks.
- **Live updates.** `partners:changed` rides the `user:<id>` topic Buddy
  already joins; the web handles both events in one bridge, since a socket
  holds one channel per topic.
- **Web.** Club › Μέλη shows the Partners card above the members list only
  where the club offers it to a member (intro, deck, paused or hidden by
  staff); `/partners/[id]` is the conversation; matches sit in Μηνύματα next
  to Buddy's; Κοινοποίηση & ορατότητα has the switch and blocked people;
  staff get `partner` rows in the report queue and the gym's switch beside
  member groups.
- Follow-ups: TD-106.
