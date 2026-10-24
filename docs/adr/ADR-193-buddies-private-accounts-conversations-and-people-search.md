# ADR-193: Buddies, private accounts, person-to-person conversations and people search
Date: 2026-10-24
Status: Accepted

## Context
ADR-142 let a member follow people, boxes and open clubs. Every follow of a
person was a request the person accepted, so every account worked like a
private Instagram account. The Feed's «Τα clubs μου» already merged the
profile posts of accepted follows, so posts from followed people reached the
Feed even outside shared clubs. Three things were missing (ANR, 2026-10-24):

- no notion of *friends*: you could only follow, with no mutual status;
- direct messages lived only in the gym's tenant (`messaging_threads`), so
  two people could write to each other only while both were active members
  of the same gym, and someone with no gym could not write to anyone;
- people search covered only the members of the current gym, and the
  Connections search only filtered people you already followed.

ANR decided (2026-10-24, decision card and thread):

1. Friends are **mutual follows** and are called **Buddies** (no second
   graph). Today's Buddy για στήριξη (ADR-160) gets another name.
2. Accounts are **private by default**, with a switch to go public.
3. You can **message all your Buddies** whether or not you share a gym or a
   club. Everyone else lands in **message requests**. Blocking works
   everywhere.
4. **Search anyone who is not private**, by @handle or display name, ranked
   by shared clubs, then Buddies, then people nearby, with a "Show me in
   search" opt-out.
5. The Feed stays **newest first** (vision §4 principle 2), and its tab is
   renamed because it is no longer only club posts.

## Decision

### 1. Buddies = mutual active follows
No new table. Two people are Buddies when each has an `active` follow of the
other in `community_follows`. Profiles, Connections rows and search results
carry `buddy: true`, and Connections gets a «Buddies» tab. Unfollowing ends
the Buddy status at once, because the status is derived and never stored.

### 2. Private account and search opt-out
`community_social_settings` gains `private_account` (default `true`, so
nobody's exposure changes) and `searchable` (default `true`). A missing
settings row reads as private and searchable.

- Following a **private** person stays a request. Following a **public**
  person is `active` at once, and they get a `new_follower` notification
  instead of `follow_requested`. Row security enforces this rule as well:
  the follower's insert policy allows `active` for a person only when the
  definer function `palee_user_is_public(uuid)` says so.
- When someone goes public, their waiting requests are accepted in the same
  call, as Instagram does. Going private again leaves current followers in
  place.

### 3. Person-to-person conversations (`Palee.Conversations`)
A new account-scoped bounded context, separate from the gym's tenant
messaging. Club ≠ Box (vision §4 principle 6): the gym's threads (box,
coach, class, assignment, and the older gym-scoped direct threads) stay a
service relationship with their outbox, analytics and staff statistics. The
social one-to-one chat belongs to the two people and follows them across
gyms, just like `buddy_messages` (ADR-160) does.

- `person_conversations`: one row per pair, ordered `user_a_id < user_b_id`
  and unique per pair. Each side has its own `folder` (`inbox | requests |
  declined`) and its own `read_at`. The row also stores `started_by_id`,
  `last_message_at` and `last_author_id`. Row security lets only the two
  people read it or write it. A guard trigger keeps the pair and the starter
  fixed, lets each side move only its own read mark, and never lets one side
  decline for the other.
- `person_messages`: immutable rows (body 1–2000 characters, optional
  `client_operation_id`, unique per author for idempotent retries) that
  carry the pair for row security. The author must be one of the pair and
  must not be blocked by the other person, and the database checks this on
  insert.
- **Where a new message lands** (pure `Conversations.Domain.ConversationPolicy`):
  - blocked either way: the conversation does not exist (404);
  - Buddies, a shared active gym membership or open-club membership, or the
    recipient follows the sender: the recipient's **inbox**;
  - anyone else: the recipient's **requests**.

  The recipient accepts a request, or replies to it, which also accepts it.
  Declining moves it to `declined`, which the recipient never sees again.
  The sender is not told. If the relationship later qualifies (for example,
  they become Buddies), the next message moves it back to the inbox.
- Live updates go on the person's own `user:<id>` topic as
  `conversation:changed` events carrying ids only. Clients refetch what they
  show, as Buddy updates already do (ADR-160).
- Notifications: `person_message` (inbox only, says who wrote and never
  what) and `message_request` (once per conversation, when it first lands in
  requests).
- API (personal session, no gym needed): `GET/POST /api/me/conversations`,
  `GET /api/me/conversations/unread-count`,
  `GET/POST /api/me/conversations/:id/messages`,
  `POST /api/me/conversations/:id/read`, `POST /api/me/conversations/:id/accept`,
  `POST /api/me/conversations/:id/decline`.

### 4. People search
`GET /api/people-search?q=` (personal session, search rate limit). The
definer function `palee_people_search(handle_term, name_term, lim)` matches
the handle by prefix and the folded display name (`users.search_text`,
trigram index) and returns `(user_id, relation)`:

| rank | relation | who |
|---|---|---|
| 1 | `club` | shares an active gym or open club (unless they hide from «Μέλη» and are not searchable) |
| 2 | `buddy` | mutual follow |
| 3 | `follow` | a follow in either direction |
| 4 | `nearby` | public and searchable, sharing a home neighbourhood |
| 5 | `public` | public and searchable |

The search never returns the viewer, demo people (ADR-184) or anyone blocked
either way. Private or unsearchable people show up only through ranks 1–3,
which are people you already know.

### 5. Feed scope label
«Τα clubs μου» becomes **«Οι δικοί μου» / "My people"**, the vision's own
phrase ("my people (feed and clubs)"). The behaviour does not change: clubs,
people you follow (Buddies included) and boxes you follow, newest first,
next to «Γύρω μου».

## Rationale
- A derived Buddy status cannot drift from the follow graph, and it needs no
  second set of requests.
- Private by default keeps today's exposure for every existing account.
  Going public is a choice the person makes.
- A separate account-scoped context gives one place for person-to-person
  rules (requests, declines, blocks) without weakening tenant isolation on
  `messaging_*`, whose rows, outbox and staff metrics are per gym.
- Doing search in one definer function lets ranking, privacy and block rules
  use other people's settings without opening those tables to row reads.

## Alternatives Considered
- **Separate friends table with its own requests**: rejected, because it
  would mean two graphs to keep in sync and two kinds of request.
- **Account-scoped rows inside `messaging_threads` (`organization_id IS NULL`)**:
  rejected. Every adapter, channel, outbox and analytics path assumes a gym,
  so loosening the tenant policy there risks cross-tenant leaks for little
  gain.
- **Ranked (algorithmic) feed**: rejected by vision §4 principle 2.

## Consequences
- The inbox (✈) shows person conversations and the gym's threads together.
  A member who already had a gym-scoped direct thread with someone keeps it
  as history, and new messages from profiles and search go to the person
  conversation.
- Typing indicators are not part of person conversations yet.
- The rename of today's Buddy για στήριξη is a UI copy change only. Code,
  tables and routes keep `buddy_*`, and the vision doc records the new name.

## Implementation Notes
- Migration `20261214200000_buddies_private_accounts_and_conversations`.
