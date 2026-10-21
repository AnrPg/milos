# ADR-138: Community context: clubs, channels and posts
Date: 2026-10-16
Status: Accepted

## Context
The product vision (§7.1) makes the social feed the home of the member app:
a club bar, posts that always show their origin (`Box Κυψέλη › #wod-σήμερα`),
a compose sheet with an audience picker, and a club page with channels whose
governance is fixed (who creates, who writes, who is in). Decision D1
(2026-10-15) put this in a new `Community` bounded context; Messaging keeps
direct messages and the coach inbox. D6–D9 settled the `#wod-σήμερα`
leaderboard, class-slot groups, Phase 1 moderation and text-only media.

## Decision
1. **Tables** (one migration, `20261017118000_create_community`), every row
   carrying the `organization_id` of the gym that runs the club, with
   composite `(id, organization_id)` foreign keys so a row can never point
   into another gym:
   - `community_clubs(kind gym|open|member_group|pt_squad|season, name,
     join_policy, archived_at)`; one `gym` club per organization. A gym club
     has no stored name: it is named and branded by its gym, so a rename or
     rebrand shows at once.
   - `community_channels(club_id, kind announcements|wod|challenges|class_slot|season|custom,
     name, write_policy staff|members|participants|system_and_members,
     membership everyone|opt_in|invite, context_type, context_id, position)`;
     one of each built-in kind per club, one channel per context (e.g. a
     class series). Built-in channels store no name; clients translate the kind.
   - `community_club_memberships(club_id, user_id, role, notify_level all|announcements|none)`.
   - `community_channel_memberships(channel_id, user_id, source opt_in|suggested|invited|auto)`.
   - `community_posts(club_id, channel_id, author_id, audience, body,
     attachment_type, attachment_id, attachment, client_operation_id,
     pinned_at, hidden_at, hidden_by_id, deleted_at)`.
   - `community_post_reactions(post_id, user_id, kind)` and
     `community_post_comments(post_id, author_id, body, deleted_at)`.
2. **A gym club's members are the gym's active members, never a copy.**
   The plan proposed syncing `community_club_memberships` from membership
   events. Organizations has no single membership event (joins, invitations,
   role and status changes each write differently), and a copy can drift.
   Instead membership and role are derived on every read from
   Organizations' public API: an active membership makes you a member, a
   staff role (owner, admin, coach) makes you `staff`. The membership table
   stores only what a member chose (notification level, written on first
   change) and, in Phase 2, the memberships of club kinds that are not
   derived. Nothing needs syncing, so nothing can drift.
3. **RLS.** Every table has the usual tenant policy (writes happen in the
   gym's scope) plus a `FOR SELECT` policy `palee_acting_user_belongs_to(organization_id)`,
   so a member's personal session reads the clubs and posts of every gym
   they actively belong to. That is how the club bar and the cross-gym feed
   read without one request per gym.
4. **Provisioning.** `Community.provision_gym_club/1` creates the club and its
   built-in channels (`#ανακοινώσεις` staff-written, everyone in;
   `#wod-σήμερα` system and members, everyone in; `#challenges`
   participants, opt-in). It is idempotent and runs inside organization
   provisioning (`TenantDefaults`, ADR-133), from the hourly
   `ProvisionGymClubsJob` (backfill and self-heal, e.g. when a built-in
   channel is added later), and before `GET /api/me/clubs` for a gym the job
   has not reached yet.
5. **Governance** is one pure module, `Community.Domain.ChannelPolicy`:
   who may post (`staff` → staff only; `participants` → staff or joined;
   `members`/`system_and_members` → any member), which channels reach the
   feed (`everyone`, or joined), which a member may join or leave
   (`opt_in`), and moderation (D8: authors delete their own posts; staff
   hide, delete and pin).

## Rationale
Deriving gym membership keeps one source of truth and removes a whole class
of sync bugs at the cost of one Organizations read per request, which the
member app already makes. The cross-gym read policy reuses the membership
predicate the root tenant tables use, so it adds no new trust boundary.

## Alternatives Considered
- **Sync club memberships from PubSub events**: needs an event on every
  membership write path and a reconciliation job for missed events; rejected
  for drift risk.
- **Clubs inside Messaging**: rejected by D1; channels are broadcast spaces
  with governance, not conversations.
- **One request per gym for the feed**: simpler RLS but N round trips and a
  client-side merge; rejected.

## Consequences
- Every new built-in channel kind is added to `ChannelPolicy.gym_channels/0`
  and reaches existing gyms within an hour.
- Phase 2 open clubs, member groups and PT squads will store their
  memberships explicitly and need their own read policy for non-members.

## Implementation Notes
- M6: `community_*` tables (migration `20261017118000`) with tenant RLS plus a
  read policy for members of the club's gym, so the cross-gym feed reads in
  the user's session. `ProvisionGymClub` runs inside gym provisioning, on
  first read (`ClubScope`) and hourly (`ProvisionGymClubsJob`).
- M7: posts, kudos and comments (`Community.Commands.Posts`), the feed query
  with a keyset cursor (`FeedCursor`), realtime topic `community:club:<id>`.
  Attaching a journal entry snapshots it and moves it to the `posted` rung;
  deleting the post restores the previous rung (`PostAttachment`).
- M8: `GET /community/wod-today` (`GetWodTodayCard`) ranks the day's
  executions and logged scores by the WOD's scored section
  (`Execution.Domain.ScoreRanking`); private results never show, and only
  members who opted in to leaderboards appear (plus the viewer's own row).
  Entering a challenge joins `#challenges` with source `auto`. Class-slot
  groups (D7): `SyncClassGroups` keeps one opt-in channel per active class
  series, archives the rest, and offers the group (`suggested`) to members
  with 3 approved bookings of that class in 28 days; leaving stores
  `dismissed`, so it is not offered again.
