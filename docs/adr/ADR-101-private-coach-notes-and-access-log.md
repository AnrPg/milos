# ADR-101: Private Coach Notes and Their Access Log
Date: 2026-10-12
Status: Accepted

## Context
Coaches need notes about a client that the client never sees (injury
context, motivation, plans). Today only client-visible coaching messages and
assignment notes exist. Gym owners must be able to read coaches' notes;
admins only with the coach's consent and with the coach knowing.

## Decision
- A `CoachNote` belongs to a coach and a client in a gym: body, created and
  updated times. Only its author edits or deletes it. The client never sees
  it.
- **Readers**: the author; owners always; admins only while the author's
  membership setting `notes_visible_to_admins` is on (default **on**);
  head coaches do not read other coaches' notes.
- **Access log**: every read of someone else's note by an owner or admin is
  stored (`reader`, `note`, `read_at`). When the reader is an admin the coach
  gets a `coach_note_viewed` notification naming the admin, the note and the
  time. Coaches see the log of their notes.

## Rationale
Owners carry responsibility for client safety and staff conduct, so their
access is unconditional; admins are colleagues of the coach, so consent plus
transparency balances oversight and trust.

## Alternatives Considered
- Notes visible to all staff: rejected; notes may hold sensitive context.
- Notifying the coach on owner reads too: possible later; the log already
  records them.

## Consequences
New table pair with RLS (`coaching_notes`, `coaching_note_reads`); a
notification type following the TD-023 checklist; a coach setting.

## Implementation Notes
To be completed with the implementation.
