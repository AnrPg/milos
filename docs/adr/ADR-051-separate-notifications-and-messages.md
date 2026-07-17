# ADR-051: Separate Notifications and Messages Presentation
Date: 2026-07-17
Status: Accepted

## Context

Chat delivery creates a `chat_message` notification record for Web Push and
recipient-scoped realtime invalidation. Rendering that delivery record in the
notification inbox while also showing the same content in its conversation
duplicates UI, unread badges, and read actions.

Notifications and Messages also support different user intents. Notifications
are passive updates to review, while Messages is an active workspace for finding
people, reading conversation history, and composing replies.

## Decision

Keep separate authenticated navigation controls for Notifications and Messages.

`chat_message` notification records remain durable delivery facts so they can
drive Web Push and recipient-scoped realtime refreshes, but they are hidden from
the notification inbox read model, notification unread count, and bulk-read
actions. Chat content appears and is counted only through Messaging-owned
threads. The Messages badge counts unread incoming threads; outgoing messages
never increment it.

## Rationale

Separate controls match the two interaction models and make starting a
conversation discoverable without first opening a notification panel. Hiding
chat delivery records from the notification read model prevents duplication
without sacrificing reliable push or realtime delivery.

## Alternatives Considered

A unified Inbox with Updates and Messages tabs was rejected because opening a
notification surface to initiate or browse conversations is counterintuitive
for this application.

Rendering chat notification cards that link to Messages was rejected because
the same message would remain visible and counted in two places.

Merging Messaging and Notifications persistence was rejected because it would
collapse bounded contexts with different ownership and lifecycle semantics.

## Consequences

Notification queries, unread counts, and bulk-read actions exclude
`chat_message`. Push dispatch and recipient realtime broadcasts remain
unchanged. The frontend maintains two controls and two independent unread
counters, each with a single source of truth.

## Implementation Notes

The navigation retains its dedicated Chat control and message-thread panel.
The notification domain hides `chat_message` from every inbox read path while
preserving the record for Web Push and realtime invalidation. Focused tests
cover delivery-record persistence, notification exclusion, incoming-only
message counts, and read-pointer decrement behavior.
