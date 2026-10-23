# ADR-153: Club events, attendees and guest passes
Date: 2026-10-20
Status: Accepted

## Context
Plan §5a board 8 (P2-M5) gives every club an Events tab: staff and coaches
publish a run, a picnic or a competition day; people say «Θα έρθω»; friends
come on a member's guest pass; open events show on the box's public page;
staff take the money at the door, mark who came and, afterwards, offer a trial
to the people who came and aren't members. ADR-144 deferred events to this
milestone. Clubs, channels and posts (ADR-138, ADR-143), trials (ADR-144) and
Finance already exist and must not learn about events.

## Decision
1. **Community owns events.** `community_events` (one row per occurrence: club,
   time, a box location *or* a named place, capacity, price, who may come,
   cover, `series_id`, cancel, `reminder_sent_at`, `trial_offer_sent_at`,
   `post_id`) and `community_event_attendees` (one row per person and event:
   `status` going · waitlisted · cancelled, `source` member · open · guest,
   `invited_by_id`, payment, check-in, `late_cancel`, `removed_by_id`,
   `trial_offered_at`, `converted_at`). Rules are pure (`EventPolicy`,
   `EventSeries`); persistence goes through the `EventStore` port and its Ecto
   adapter.
2. **Who runs them.** A new capability `manage_events` (owner, admin, coach).
   Staff use «Κοινότητα › Events» under `/org/:slug/admin/community/events`;
   the same use cases serve the member app's club page
   (`/api/me/community/clubs/:id/events`), resolved to the person's tenant
   context at the club's box. Reading the staff view also suits
   `check_in` and `take_payments`; «Ήρθε» and «Πλήρωσε» need those.
3. **Weekly repeat.** «Επανάληψη κάθε εβδομάδα» creates up to 26 occurrences at
   the same local time in the box's zone (across DST), sharing a `series_id`.
   Each occurrence has its own attendees. Edit and cancel take a scope: `this`
   (default) or `following`; following occurrences move by the same day shift
   to the new local time and duration (`EventSeries.follow/4`).
4. **Places hold under concurrency.** Every change to who holds a place (answer,
   withdraw, staff freeing a place, a raised capacity) runs with the event row
   locked (`SELECT … FOR UPDATE`); a freed place goes to the longest-waiting
   person in the same transaction and they are notified. Answering twice
   changes nothing. Giving up a place within 2 hours of the start is a late
   cancel; staff freeing a place never is.
5. **Who can come.** The club's members; anyone signed in on an
   `open_to_non_members` event (these are listed on `/api/boxes/:slug/events`);
   and guests holding a going member's invitation, up to `guests_per_member`
   when `guest_pass_allowed`. Names of who's going show only to people who can
   see the club; everyone else sees the count.
6. **Guest pass = signed token.** `EventInvites` signs `{event, box, inviter}`
   with `Phoenix.Token` (salt `community-event-invite-v1`, 60 days) through the
   `SignedToken` port; no table. The token opens the event page
   (`/events/:id?invite=…`), which says who invited and whether a place is
   left; joining re-checks the inviter is still going and has guests left,
   under the lock. The attendee keeps `invited_by_id`, which referral rewards
   (P2-M8) read; Finance referral events are not written here because they
   need a Finance membership and program the guest doesn't have.
7. **Paid events.** Payment happens at the box. «Πλήρωσε» records it once on the
   attendee and, through the application port `Ports.EventPayments`
   (adapter `FinanceEventPayments`), issues a Finance receipt (manual invoice
   plus payment) when the person has a Finance record at the box; otherwise
   the payment lives on the attendee only and Finance is not touched. Both
   happen in one transaction. Staff can free unpaid places.
8. **Feed card.** Publishing posts a card (`attachment_type = "event"`, with a
   snapshot) in the club's #ανακοινώσεις; every occurrence links it
   (`post_id`), and the feed attaches the live event (a series shows its next
   occurrence). `event` is not offered as a profile or compose attachment.
9. **Notifications** (12 locales): `community_event_waitlist_promoted`,
   `community_event_cancelled`, `community_event_changed` (time or place),
   `community_event_reminder` (2 hours before; `EventRemindersJob` every 10
   minutes claims `reminder_sent_at` atomically, so it goes once; a later start
   owes a new one), `community_event_guest_joined`,
   `community_event_trial_offer` and `community_event_message`
   («Μήνυμα σε όλους»). Each carries a dedupe key.
10. **Trial offer.** Once per event (claimed via `trial_offer_sent_at`), after it
    ended, to people who came (checked in) and aren't active members, at a
    published box with trials on. The link opens the box's trial sheet with
    `referral_event_id`; `scheduling_trial_requests.referral_event_id` (checked
    to belong to the box, source `event`) records it, and the event's numbers
    count those requests. Joining the box within 30 days of attending marks
    the attendee converted (`membership_activated` → `EventReactions`).
11. **Lists.** A club's upcoming or past events, upcoming events across the
    person's clubs, their own events at any box (`/api/me/events`), the box
    page's open events, and going events in the calendar feed.
12. **Tenancy.** Both tables carry `organization_id` with the tenant policy, are
    in the Community tenant data policy and the audit's ready tables. Personal
    read policies let a person read events of clubs they can see, open events
    and events they're on (`palee_acting_user_event_ids`), and their own
    attendee rows.

13. **Member-group events.** An event may belong to a member group
    (`community_events.channel_id`, a `member_group` channel of the same club).
    The admin of an active group creates them from the club page
    (`channel_id` in the create body), and edits and cancels them; staff with
    `manage_events` manage them like any other, and running a group gives no
    say over club events (`EventPolicy.manage_check/2`). They are always free,
    never open to non-members and take no guest passes: `EventPolicy.group_terms/1`
    overrides whatever was asked, the changeset validates it and a check
    constraint holds it. Only the group's members see them, see who's going
    and say they come (`belongs?`, `visible?`, `can_rsvp?`); their card goes in
    the group. From a personal session, RLS shows a group event to the group's
    members (`palee_acting_user_group_ids`) and the box's staff.
    *Changed by ADR-185:* group events are no longer forced. The group's admin
    picks the price, guest passes and the audience (`community_events.audience`:
    the group, the club or everyone). `group_terms/1` and its check constraint
    were removed, and only `group` events keep the visibility above.
14. **Late cancels for staff.** The staff attendee list marks «Ακύρωσε αργά»
    (`late_cancel` with `cancelled_at`) and gives each person's late cancels at
    the box over the last 90 days (`late_cancels_90d`); every event's numbers
    count its late cancels.

## Consequences
- The club page's Events tab and «Κοινότητα › Events» have an API; the web
  follows in the second half of P2-M5.
- A group archived or no longer active keeps its events, but only staff can
  change them.
- A person's guest pass works only while they are going; withdrawing doesn't
  remove guests already in.
- Payments of people without a Finance record don't appear in Finance reports;
  the event's numbers show them.
- Moving a series that crossed a DST change keeps local times, so UTC gaps
  between occurrences differ by an hour around the change.
