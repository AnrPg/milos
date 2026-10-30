# ADR-282: Anyone writes to a box, and the box answers from one shared inbox
Date: 2026-10-30
Status: Accepted

## Context
A plain member had no way to message their box. «Επικοινωνία με το box» on
`/me/payments` led to `/messages?filter=clubs`, which was empty: the gym's
thread with a member (`messaging_threads.context_type = 'box'`, ADR-140 §6)
could only be started by staff, and `/b/:slug/chat` (ADR-144) only worked
for published boxes and for people who had asked for a trial.

Two faults sat underneath. The thread's readers were frozen when it was
opened (`list_staff_user_ids`: owners, admins and coaches), so coaches
received messages they could not answer as the box, front desk was left out,
and anyone hired later never saw older threads. Staff had no way to see
what was waiting for an answer.

ANR decided the five questions of the mockup
(`/mnt/project-files/milos/box-messages/box-messages-mockups-2026-10-30.html`)
on 2026-10-30: Q1 C, Q2 A with coaches as the contact point for some
questions, Q3 A, Q4 A, Q5 A.

## Decision
1. **Anyone with an account writes to a published box** from its page
   (`POST /api/boxes/:slug/conversation`). A member also reaches their own
   box when its page is not published. Someone who is not a client, now or
   before, shows as «Νέος» in the inbox, may send three messages until the
   box answers (`429 awaiting_box_reply`), and can be blocked by the inbox
   (`messaging_box_blocks`; `403 blocked_by_box`). Clients are never held
   back and cannot be blocked (`422 client_not_blockable`).
2. **One shared inbox worked out from the roles at read time.** Whoever
   holds `message_from_box` (owner, admin, front desk, accountant) reads and
   answers every box thread of the gym. Listing threads gives them a row
   (read marker) in each box thread they lack one in; reading, sending and
   marking read check the role first (`BoxInbox.authorize`), so someone who
   loses the role loses the threads. No setting.
3. **Coaches as contact point.** The topic «Προπόνηση» (`training`) brings
   in the person's coaches (active coaching relationship), or the head
   coaches (coach scope `all`) when they have none. «Φέρε τον coach» lets
   the inbox bring any coach of the box into a thread
   (`GET|POST /api/org/:slug/me/threads/:id/coaches`). A coach reads a box
   thread only while brought in (`messaging_participants.joined_as =
   'coach'`) and still a coach there, and answers as the box
   (`box_message`, never metered).
4. **Where it shows.** The person reads every box they talk to in Μηνύματα
   › Box (`GET /api/me/box-conversations`, members included now) and writes
   on `/b/:slug/chat`; every «Επικοινωνία με το box» opens that chat with
   the topic preset from where it was pressed (`?topic=payment` from
   Πληρωμές). Staff read the threads in Μηνύματα › Box with «Αναπάντητα»
   (the person wrote last) and «Όλα»; each row carries `last_message` and
   `box_person` (`newcomer`, `blocked`). The person's own box thread is left
   out of the gym's thread list, as it lives in their box conversations.
5. **Notifications.** A person's message notifies the whole inbox (and the
   coaches brought in) with the new type `box_inbox_message` («Γιώργος Π.
   έγραψε στο Milos method»), shown in the bell, until someone answers;
   after that only the last one who answered hears, while they still may
   read the thread. The box's answers notify the person only
   (`box_message`, opening `/b/:slug/chat`). A coach brought in hears who
   brought them.
6. The person may tag their own messages with a topic
   (`messaging_messages_topic_check` admits `chat`), and `training` joins
   the topics.

## Rationale
Rules sit in one pure module (`Messaging.Domain.BoxInboxPolicy`): access,
who writes for the box, recipients, the handler and the newcomer limit. The
application service `BoxInbox` gathers the facts from Organizations
(capabilities, roles, standing) and Coaching (relationships). Working the
audience out from roles at read time fixes the frozen-readers bug for good
and needs no sync on role changes. The participant row stays as the read
marker and as the record of a coach who was brought in.

## Alternatives Considered
- Only active clients write (Q1 A) or past and present clients (Q1 B):
  rejected by ANR in favour of everyone, with blocking and the newcomer limit
  against spam.
- A setting for which roles receive (Q2 B) or a single contact person
  (Q2 C): more configuration, or a single point of failure.
- A topic sheet before the chat (Q3 B) or tickets (Q3 C): an extra step,
  and colder than a chat.
- A separate console helpdesk page (Q4 B) or messages only in the member's
  profile (Q4 C): a second home for the same thing, or no overview.
- Notify everyone on every message (Q5 B) or only the owner (Q5 C): noise,
  or a bottleneck.
- Syncing participant rows on every role change: drift-prone; read-time
  derivation needs no hooks.

## Consequences
- Migration `20270326100000_box_inbox`: `joined_as`, the wider topic check,
  `messaging_box_blocks` (tenant RLS), the `box_inbox_message` type. Old
  box-thread rows of people outside the inbox roles (the coaches the old
  code added) are removed.
- The limit of three unanswered messages for a newcomer is a constant in
  `BoxInboxPolicy`; ANR may change it.
- Role grants cannot give coaches `message_from_box`; coaches take part
  only through point 3.

## Implementation Notes
- `Messaging.join_box_threads/1` inserts the missing rows with one
  `INSERT … SELECT … ON CONFLICT DO NOTHING` inside the gym's scope.
- `MyBilling` now always gives a client's box chat slug (published or not),
  so «Επικοινωνία με το box» opens `/b/:slug/chat`.
