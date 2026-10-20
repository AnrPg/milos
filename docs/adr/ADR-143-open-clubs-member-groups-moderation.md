# ADR-143: Open clubs, member groups and moderation
Date: 2026-10-20
Status: Accepted (P2-M4)

## Context
Phase 2 opens the community beyond the gym club (plan D6, §5a board 7): staff run
open clubs anyone near the box can join, members start their own groups inside the
gym club when the owner allows it, and anyone can report what doesn't belong.
Phase 1's community context (ADR-138) had one club per gym and staff-made channels.

## Decision
1. **Open clubs are clubs.** `community_clubs.kind = open`, made only by staff
   (`manage_community`), with a description, a cover (`box_photo` media, ADR-148) and
   `join_policy open|approval`. People who belong to or follow the box join through
   `community_club_memberships` (`status member|requested`). Each open club has
   #ανακοινώσεις (staff write) and #γενικά (members write). It shows on the box page.
2. **Member groups are channels.** `community_channels.kind = member_group` inside the
   gym club, with `created_by_id`, `description`, `join_policy open|request`,
   `status pending|active|declined`, `last_post_at` and `archive_warned_at`. Group
   memberships carry a `role member|admin`; the creator is the first admin. A group
   admin moderates inside the group like staff (hide, pin, delete, answer requests).
3. **Owner setting.** `community_settings.member_groups = none|approval|free`
   (default `approval`). Under `approval` a proposal waits for staff
   (`moderate_community`), who are notified.
4. **Leaving rules.** The last admin hands over before leaving (`hand_over_first`);
   the last member leaving archives the group. Whoever started an archived group can
   bring it back and becomes its admin if no one runs it.
5. **Quiet groups.** `ArchiveQuietGroupsJob` (daily, Oban cron) warns admins at 50
   days without a post and archives at 60 once warned. A new post clears the warning.
   The rules live in the pure `GroupPolicy`.
6. **Reports.** `community_reports(target_type post|comment|channel, target_id,
   reporter_id, reason spam|harassment|inappropriate|other, note, status,
   resolution)`, one per reporter and item. The item disappears for the reporter at
   once; no autohide. Staff work one grouped queue (Απόκρυψη, Διαγραφή, Δεν
   χρειάζεται τίποτα, Αρχειοθέτηση ομάδας); acting closes every report on the item.
   `ReportPolicy` maps actions to target types.
7. **Personal routes for posting anywhere.** Posts, kudos, comments and moderation
   for any club the member reaches go through `/api/me/community/*`; writes run in the
   scope of the gym that runs the club (`ClubScope.write_context`). Open-club reads
   for non-members use SECURITY DEFINER helpers (`milos_open_club_member_counts`).
8. **«Μέλη».** `/api/me/clubs/:id/members` lists everyone but the reader, coaches
   first, with a search. `community_social_settings.hide_from_members` lets a person
   stay off the list (`milos_hidden_member_ids`).
9. **Capabilities.** `moderate_community` (owner, admin, coach) and
   `manage_community` (owner, admin); see rights-per-account-type.
10. **Realtime.** Group changes broadcast `channels_changed` on
    `community:club:<id>`, so club bars and group lists refresh.

## Consequences
- The club page has Ροή · Κανάλια · Events · Μέλη; Events stays «Σύντομα» until P2-M5.
- «+ Βρες» lists open clubs of boxes the person belongs to or follows and groups of
  their gyms; clubs nearby come with Γύρω μου (P2-M6).
- Staff use «Κοινότητα» (Ομάδες · Αναφορές · Ανοιχτά clubs); the member-groups
  setting also sits in Ρυθμίσεις next to Δημόσια σελίδα and Δοκιμαστικά.
