# ADR-053: Display usernames and device push controls
Date: 2026-07-17
Status: Accepted

## Context

Usernames need to be readable exactly as a person entered them while identity
lookup, uniqueness, and search need a stable ASCII value. Browser-push controls
also need to be available after opt-in without occupying the notification inbox.

## Decision

Store a display username alongside the existing normalized username. The
normalized value remains the unique lookup key; display values are returned to
clients. Registration accepts letters, numbers, and underscores only, with a
minimum of three characters. Passwords require four or more non-whitespace
characters.

The inbox shows browser-push setup only until the current device is enabled.
The enabled-device status and disable action live in Profile > Security.

## Rationale

Separating presentation from lookup retains deterministic authentication and
search while respecting the user's chosen capitalization and script. Moving an
already-enabled control to Security keeps the inbox focused on delivery events.

## Alternatives Considered

Storing only the display value was rejected because case- and script-insensitive
search would become inconsistent. Keeping the enabled-device control in Inbox
was rejected because it is an account-security preference, not an inbox item.

## Consequences

The `users` table gains a non-null `display_nickname` column, backfilled from
existing normalized values. Existing APIs retain their `nickname` field but now
present the display value; persistence queries continue to use normalized
values. Greek and Cyrillic transliteration is supported at the domain boundary.

## Implementation Notes

Implemented with a non-destructive backfill migration, pure registration-policy
validation, and client-side per-field validation tooltips. Existing users retain
their current lower-case nickname as their display value until they edit it.
