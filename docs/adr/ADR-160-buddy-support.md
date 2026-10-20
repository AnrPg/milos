# ADR-160: Buddy για στήριξη and the coach's weekly wellness summary
Date: 2026-10-20
Status: Accepted

## Context
Plan §5 P2-M12 and vision §7.8 add Εγώ › Buddy για στήριξη: one or two
trusted people (a partner, a friend or the coach), with mutual acceptance,
who receive only what the member explicitly sends with «Χρειάζομαι
στήριξη»; quick replies «Είμαι εδώ», «Πάμε βόλτα;», «Πάρε με τηλέφωνο»; an
optional weekly summary with counts only; either side can leave at any
time; the coach gets a weekly summary only with permission. The ethics
checklist (plan §6, vision §8.6) and ADR-147 keep cravings private by
default and forbid comparison and medical claims.

Board 15 picked every recommended option: up to two buddies, each with what
they receive (A); anyone you know here or a link for someone not on Milos,
invitations expiring after seven days (A); «Χρειάζομαι στήριξη» from
Λιγούρα and from a quick button, with a 5-second undo and nothing about the
craving shared (A); a push with quick replies that opens a private
conversation, the sender's phone only when shared (A); a calm card after
ten minutes without a reply, with help lines as information (A); weekly
counts chosen per person (A); quiet leaving, quiet hours, a rate limit and
block ending it at once (A), plus phone sharing off by default.

M11 (ADR-159, Ευεξία and Λιγούρα) is built in parallel. It owns
`wellness_entries` and `craving_entries` and stamps «Χρειάζομαι στήριξη»
on a craving, then calls a port for the buddy side. On M11's board the
owner decided that the coach sees nothing of wellness unless the member
turns on «Ευεξία · εβδομαδιαία σύνοψη» (counts only), and sees cravings,
as a count and times, only with a second toggle «Λιγούρες στη σύνοψη»;
those toggles and that summary belong to this milestone. ADR-159 is M11's,
so this is ADR-160.

## Decision
1. **A Buddies context owns the data, account-scoped.** Six tables keyed
   on the asking member's `user_id`, deleted with the account:
   `buddy_links` (requester, `buddy_user_id` null until an invite link is
   claimed, the link's token digest, `status
   pending|active|declined|ended|expired`, `receives_weekly_summary`,
   `expires_at` seven days out, `started_at`, `ended_at`, `ended_by_id`; at
   most one open link per pair), `buddy_settings` (quiet hours as local
   times in `tz`, `share_phone` off by default, `phone`),
   `support_requests` (optional message of at most 280 characters, `source
   craving|quick`, an opaque `source_ref`, `undone_at`, `delivered_at`,
   `nudge_sent_at`), `support_request_deliveries` (who received it,
   `delivered_silently`, `replied_at`), `support_replies` (`kind
   here|walk|call|text`, optional words, the conversation it opened) and
   `wellness_summary_grants` (scope `wellness|cravings`, one row per grant,
   a withdrawal closes it).
2. **Row security for two parties.** A link, delivery or reply is visible
   to and writable by its two people (`user_id` or `buddy_user_id` is the
   session user); a support request to its sender, and to a buddy only once
   it was delivered and not taken back; settings and grants to their owner.
   Narrow SECURITY DEFINER functions answer what crosses people:
   `milos_buddy_relation` (coach, club or follow, for the session user
   only), `milos_buddy_candidates`, `milos_buddy_invite_preview` and
   `milos_buddy_claim_invite`, `milos_buddy_quiet_hours` and
   `milos_buddy_shared_phone` (only across an active link),
   `milos_buddy_summary_requesters` (ids and zones for the job).
3. **The link's life is a pure state machine** (`LinkPolicy`): invite →
   pending; the buddy accepts or declines; either side leaves (a requester
   may also withdraw a pending invite); a block ends it at once
   (`Application.Buddies.end_for_block/3`, for the blocking feature to
   call); a pending invite past seven days reads as expired and is marked
   so lazily. At most two open (pending or active) invites of one's own,
   checked under an advisory lock. Only an invite and an acceptance notify;
   declining and leaving are quiet, the other side sees it on their page.
4. **Who can be invited** (`Eligibility`): one's coach, someone sharing an
   active gym or open club, someone one follows or who follows one; anyone
   through an invite link the member shares themselves (only the token's
   SHA-256 digest is kept). The public `GET /api/buddy-invites/:token`
   shows who invited and whether the link works; claiming needs sign-in
   and is the acceptance. The people search lists coaches and follows, and
   with a term of two letters or more, people of a gym or open club in
   common who did not hide themselves from members.
5. **«Χρειάζομαι στήριξη»** (`SupportPolicy`) goes to every active buddy.
   It is created with its deliveries at once, but buddies are told only
   when the 5-second undo closes, by a scheduled, idempotent step
   (`SupportRequestJob` `deliver`); an undone request is never told. At
   most three requests an hour. A buddy inside their quiet hours gets it
   silently (inbox, no push: `silent` on the notification payload skips
   the push) and the sender sees «έχει ώρες ησυχίας». Nothing about a
   craving travels: the buddy sees the message and who sent it, not even
   the source.
6. **Replies and the buddy conversation.** Every buddy link has its own
   conversation (`buddy_messages`), owned by Buddies and account-scoped, so
   two buddies can always talk whether or not they share a gym; nothing
   depends on gym-scoped Messaging. Only the link's two people read it
   (row security); a message is written only by one of them, as
   themselves, into an active link, so an ended link's thread stays
   readable but read-only; only the recipient marks a message read, and a
   trigger keeps everything else of a message immutable. Bodies are at
   most 2000 characters. `GET/POST /api/me/buddies/:id/messages` (newest
   first, opaque cursor, `read_only`, `unread`) and
   `POST /api/me/buddies/:id/messages/read`; the overview carries
   `unread_messages` per link. A support reply is a quick kind or words; it
   posts into the conversation (the quick reply's text, then the buddy's
   own words) and notifies the sender once (`support_reply`); a plain
   message notifies once (`buddy_message`, naming who wrote, never what),
   so nothing is notified twice. «Πάρε με τηλέφωνο» returns the sender's
   phone to the buddy only if the sender shares it.
7. **The no-reply card** is computed (due ten minutes after a delivered
   request with no reply) and also pushed once by the `nudge` step:
   breathing for two minutes, a glass of water, a short walk, «Στείλε
   ξανά», and a help-lines link marked informational, never advice.
8. **The buddy's weekly summary** (`WeeklySummary`): on Sunday at 19:00 in
   the member's zone (`BuddyWeeklySummaryJob` every half hour), each buddy
   whose link has `receives_weekly_summary` hears counts only: hard moments
   (Λιγούρα entries of the week), how many were overcome, how many support
   requests. Never times, causes, foods, intensity or notes; one per link
   and week by dedupe key.
9. **The coach's weekly wellness summary** (`SummarySharingPolicy`,
   `WellnessSummarySharing`) follows the M11 board answer. The member's
   toggles are grants (`GET/PUT /api/me/wellness-summary-sharing`); turning
   the summary off withdraws both. `GET /api/org/:slug/staff/clients/:id/
   wellness-summary?week=` is guarded like the body route (`view_health`,
   the coach role, an active member) and returns `shared: false` without
   the first grant; with it, nights at the sleep goal, water days on goal
   and days with meals logged, built on M11's `Wellness.summarize_days/5`
   and `Wellness.week_line/1`; cravings as a count and local times only
   with the second grant. The coach session never reads the member's rows:
   after the seam and the grant pass, the counts are computed in the
   member's own session and only they leave. Every staff read, shared or
   not, is written to `wellness_access_log` (gym-scoped like
   `body_access_log`: who, which gym, which week, whether craving moments
   were shown); the member reads it at
   `GET /api/me/wellness-summary-sharing/access-log`, and the gym's rows go
   with the gym (Buddies' tenant data policy). A separate table mirrors the
   body log instead of generalising it, so body's data and routes stay as
   they are.
   **Sunday push** (`CoachWellnessSummaries`, run by `BuddyWeeklySummaryJob`):
   with the wellness toggle on, on Sunday at 19:00 in the member's zone,
   each coach with an active coaching relationship in a gym where the
   member is active, and `view_health` over them, gets
   `coach_wellness_summary` linking to the client page: the three counts
   only, never craving times; one per coach, gym, member and week. Definer
   lookups name the members and their coaches (ids only).
10. **M11 seam.** `MilosTraining.Application.Ports.SupportRequests.request/2`
    (config `:support_requests`) is implemented by
    `MilosTraining.Application.SupportRequests`, which also exposes
    `request_support/3` (a user context or id, `%{message, source,
    source_ref}`). Only the craving's id crosses, as an opaque reference.
11. **Notifications** in 12 locales: `buddy_invite`, `buddy_accepted`,
    `support_request` (with the quick replies), `support_reply`,
    `support_no_reply_nudge`, `buddy_weekly_summary`, `buddy_message`,
    `coach_wellness_summary`.

## Rationale
The asking member owns every row, so the account is the natural scope and
deletion follows the account. Two-party policies let both people see the
link they share without a definer function on every read, while the
definer functions answer only one narrow question each, as the body
context does. Delaying the push until the undo window closes is the only
way an undo can mean "nobody was told". Computing the coach summary in
the member's session after the seam keeps the coach's session away from
raw wellness rows and reuses M11's own day rules instead of restating them
in SQL.

## Alternatives Considered
- **Messaging for everything.** Messaging is tenant-scoped (threads need a
  gym), and a partner may share no gym with the member; support requests,
  quiet hours and the no-reply card are not chat concepts. Rejected: the
  pair's conversation belongs to Buddies.
- **Push immediately, undo hides it.** A push cannot be recalled.
  Rejected.
- **Coach grants per gym or per coach.** The M11 answer is one member
  toggle applying to their coaches with client access; per-coach grants can
  be added on the same table if needed.
- **A crisis or emergency flow.** Milos must not act as a medical or crisis
  service (board 15 Q5); help lines are information only.

## Consequences
- Buddies get exactly what the member sends and an optional weekly count;
  coaches get counts only with a grant.
- Buddy conversations live outside Μηνύματα; the inbox can list them
  beside gym threads later.
- There is no block feature yet; `end_for_block/3` is ready for it.
- The notification type check gains eight types.

## Implementation Notes
- Migrations `20261030100000_buddy_support.exs` and
  `20261030110000_buddy_messages_and_wellness_access.exs`; context `MilosTraining.Buddies`
  (domain `LinkPolicy`, `Eligibility`, `SupportPolicy`, `QuietHours`,
  `SettingsPolicy`, `WeeklySummary`, `SummarySharingPolicy`,
  `InviteToken`), store port and `EctoBuddyStore`, scheduler port and
  `ObanSupportScheduler`.
- Use cases `Application.Buddies`, `Application.SupportRequests`,
  `Application.BuddyWeeklySummaries`, `Application.WellnessSummarySharing`;
  workers `SupportRequestJob` (`deliver`, `nudge`, unique per request and
  step) and `BuddyWeeklySummaryJob` (cron `0,30 * * * *`).
- Routes: `/api/me/buddies` (+ `/candidates`, `/settings`,
  `/invite-links`, `/:id/accept|decline|leave`, `PATCH /:id`),
  `POST /api/me/buddy-invites/:token/claim`, public
  `GET /api/buddy-invites/:token`, `/api/me/support-requests` (+ `/:id`,
  `/:id/undo`, `/:id/replies`), `/api/me/buddies/:id/messages` (+ `/read`),
  `/api/me/wellness-summary-sharing` (+ `/access-log`), staff
  `/clients/:user_id/wellness-summary`.
- Tables are registered as personal tables in the tenancy audit; the store
  is in the architecture task's RepoContext list.
