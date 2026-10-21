# ADR-168: PT squads
Date: 2026-10-21
Status: Accepted

## Context
Vision §7.1 (channel governance) lists «PT squad · created by a coach · coach + their
clients · invite-only», and §7.10 / P3-M6 ask for it to start from `Box › Πελάτες μου`,
with membership following coaching. ADR-138 reserved a club kind `pt_squad`. The same
feature must work unchanged for a solo coach (ADR-170), whose organization is a gym of
one coach and whose «Team» club is the organization's gym club.

## Decision
1. **A squad is a channel, not a club.** Kind `pt_squad` inside the gym's club, like the
   member group (ADR-143) and the season channel (ADR-167): `membership: invite`,
   `write_policy: participants`, `created_by_id` = the coach. Its people are already in
   the gym club, so it reuses posting, the feed, pins, comments, media, reports and the
   club's realtime topic, and adds no bubble to the club bar. The reserved club kind
   stays unused.
2. **Invitation with consent.** The coach invites only their **active** clients
   (`coaching_relationships`, ADR-100). An invitation is a channel membership with the
   new source `pending_invite`; the client accepts (`invited`, a member) or declines
   (`dismissed`). Their name reaches the squad only once they accept. Leaving, being
   removed and withdrawn invitations are `dismissed`; a new invitation asks again.
   The invitee is notified (`community_squad_invited`).
3. **Membership follows coaching, twice.** Ending a relationship through
   `ManageCoachingRelationships.finish` dismisses the client from every squad of that
   coach in that gym. Independently, `ClubScope` and the squad use cases show a squad
   to a member only while their coaching with its coach is active, re-checked on every
   read (one relationships query per gym, only when the person is in someone else's
   squad), so an ending that bypasses the use case never leaks.
4. **Private to the squad.** Only the coach and members see the channel, its posts and
   its people; other staff do not (the coach's space with their clients). Posting is
   members-only, the coach moderates and pins as its admin, and reports reach staff
   through the existing report queue. Invite-only channels in general now show only to
   their participants and staff (closes a gap for the season channel too).
5. **Small and bounded.** `SquadPolicy`: at most 30 people besides the coach, at most 20
   live squads per coach, one name per coach among live squads (unique index). Squads
   never auto-archive; the coach archives and reopens; the gym's managers
   (`assign_coaches`) may also archive, for moderation.
6. **API** `GET|POST /api/org/:slug/community/squads`, `GET|PATCH /squads/:id`,
   `POST /squads/:id/invites`, `PUT /squads/:id/invite` (answer),
   `DELETE /squads/:id/membership` (leave), `DELETE /squads/:id/members/:user_id`
   (remove or withdraw), `POST /squads/:id/archive|reopen`. The overview returns the
   squads the person coaches (and archived ones), joined, invitations and, for a coach,
   their clients.
7. **Web.** «Πελάτες μου › Squads» in the staff home under the clients block; a Box
   section through a new **Box extension point** (`box-extensions.tsx`, shared with
   ADR-170's coach layout) showing invitations and joined squads, and a solo coach's
   own squads; a «Squads» card in the club's Κανάλια; the squad page
   `/clubs/:id/squads/:squadId` (posts, people, invite, rename, archive, leave).

No new tables: the data lives in `community_channels` and
`community_channel_memberships`, already covered by the Community tenant-data policy
and `Tenancy.Audit`. Migration `20261120100000_pt_squads` widens the kind and source
checks and adds the notification type by rewriting the current constraint (keeps types
other migrations added).

## Consequences
- Squads inherit every channel feature (media, comments, events later) for free, and
  every future channel rule applies to them.
- A coach who leaves the gym keeps no access (the gym club is membership-derived); their
  squads stay until a manager archives them.
- Co-coaching a squad is not supported; a squad has one coach.
