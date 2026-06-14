# Private Chat — Design Spec
Date: 2026-06-14
Status: Approved

---

## Overview

Implements a first-class private messaging system for Milos Training. Replaces three fragmented messaging primitives (`AssignmentMessage`, `AdminAthleteNote`, legacy `SendAthleteMessage`) with a unified `Messaging` bounded context. Supports context-anchored threads (per workout assignment or class slot) and free direct threads (any user to any user). Full real-time delivery via Phoenix Channels.

---

## Goals

- Any user can message any other user directly (no role restriction)
- Conversations are anchored to workout assignments and class slots, initiated by either party
- Coaching notes become a message type inside threads (visible to athlete)
- Full real-time: instant delivery, typing indicators, read receipts
- Notifications inform offline participants; no notification if already viewing the thread
- De-clutter: chat in side panels is a collapsible section, accordion with Details
- `/account/activity/chats` is a read-only historical inbox (deep in settings)
- TopNav Messages icon opens a floating panel for direct messaging

---

## Non-Goals

- Group threads with more than two participants (participant model supports it, but not exposed)
- File/media attachments (future)
- Message editing or deletion (messages are immutable)
- Push notification delivery for chat (regular web push notifications handle nudges)

---

## Section 1 — Domain Layer / Data Model

### Bounded Context: `Messaging`

Three new Ecto schemas, three new Postgres tables:

```
messaging_threads
  id             :binary_id PK
  context_type   :enum [:direct, :assignment, :class_slot]
  context_id     :binary_id | nil   ← nil for direct threads
  created_by_id  :binary_id FK → users
  inserted_at    :utc_datetime
  INDEX (context_type, context_id)   ← unique where context_type != :direct

messaging_participants
  id                    :binary_id PK
  thread_id             :binary_id FK → messaging_threads
  user_id               :binary_id FK → users
  last_read_message_id  :binary_id | nil FK → messaging_messages
  joined_at             :utc_datetime
  UNIQUE (thread_id, user_id)
  INDEX (user_id)

messaging_messages
  id            :binary_id PK
  thread_id     :binary_id FK → messaging_threads
  sender_id     :binary_id FK → users
  body          :string  [1..4000]
  message_type  :enum [:text, :coaching_note]
  inserted_at   :utc_datetime   ← immutable; no updated_at
  INDEX (thread_id, inserted_at)
```

**Read receipts** via `messaging_participants.last_read_message_id`. Unread count = `COUNT(*) FROM messaging_messages WHERE thread_id = ? AND inserted_at > (SELECT inserted_at FROM messaging_messages WHERE id = last_read_message_id)`. When `last_read_message_id` is nil, all messages in the thread are unread. No per-message read flags table.

**Typing indicators** are ephemeral — Phoenix PubSub only, zero DB writes.

**Thread uniqueness rules:**
- `direct`: canonical form = sorted participant ids; deduplication enforced in `GetOrCreateThread`
- `assignment` / `class_slot`: unique constraint on `(context_type, context_id)`

### Domain Modules

```
MilosTraining.Messaging                        ← public context facade
MilosTraining.Messaging.Thread                 ← Ecto schema
MilosTraining.Messaging.Message                ← Ecto schema
MilosTraining.Messaging.Participant            ← Ecto schema
MilosTraining.Messaging.Domain.ThreadPolicy   ← authorization: who can join/read/write
MilosTraining.Messaging.Ports.MessageStore    ← behaviour (port)
MilosTraining.Messaging.Ports.ThreadStore     ← behaviour (port)
```

### Legacy Deletions

| Removed | Reason |
|---|---|
| `Workouts.AssignmentMessage` schema + table | replaced by `Messaging.Message` (context_type: :assignment) |
| `Coaching.AdminAthleteNote` schema + table | replaced by `Messaging.Message` (message_type: :coaching_note) |
| Application use cases listed in Section 2 | replaced by Messaging use cases |

Analytics `CommunicationMessage` schema and table remain. They continue to be written as side-effects from `SendMessage`.

---

## Section 2 — Application Layer

### New Use Cases

| Module | Responsibility |
|---|---|
| `GetOrCreateThread` | Find existing thread by context or direct pair; create if absent. For direct: sorts `[user_a_id, user_b_id]` for canonical lookup. |
| `SendMessage` | Validate sender is participant. Persist message. Broadcast `new_message` to channel. Dispatch `:chat_message` notification to offline participants. Call `RecordCommunicationMessage.call_unsafe/1` as analytics side-effect. |
| `GetThreadMessages` | Cursor-based paginated history for a thread (oldest-first for chat UX). |
| `ListThreadsForUser` | List threads where user is a participant, filtered by `context_type`. Returns last message preview + unread count per thread. |
| `MarkThreadRead` | Update `participant.last_read_message_id`. Broadcast `read_receipt` to channel. |
| `BroadcastTyping` | Ephemeral only: push `typing_start` / `typing_stop` event to channel topic. Zero DB writes. |
| `AddParticipant` | Add a user to a thread. Implemented now for future group threads; not yet exposed via API. |

### Deleted Use Cases

| Deleted | Replacement |
|---|---|
| `PostAssignmentMessage` | `SendMessage` (context_type: :assignment) |
| `ListAssignmentMessages` | `GetThreadMessages` |
| `WriteAdminAthleteNote` | `SendMessage` (message_type: :coaching_note) |
| `SendAthleteMessage` | `SendMessage` (context_type: :direct) |
| `RecordCommunicationMessage` calls from Workouts/Coaching | side-effect inside `SendMessage` |

### Analytics Side-Effect Pattern

`SendMessage` calls `RecordCommunicationMessage.call_unsafe/1` after successful persist, preserving the existing analytics recording contract. Direction is inferred from `sender.role`.

### Notification Logic

After `SendMessage` succeeds, for each participant who is **not** currently subscribed to `"chat:thread:{thread_id}"` (detected via `Phoenix.PubSub.subscribers/2`), dispatch a `:chat_message` notification with payload:
```elixir
%{thread_id, sender_nickname, preview, context_type, context_id}
```

Adds `:chat_message` to `Notification.@types` enum.

---

## Section 3 — Infrastructure Layer

### DB Adapters

```
MilosTraining.Infrastructure.Messaging.EctoThreadStore
  ← implements Messaging.Ports.ThreadStore
  ← get_or_create_direct/2
     get_or_create_context/3 (context_type, context_id, created_by_id)
     list_for_user/2 (user_id, context_type filter)
     get_with_participants/1

MilosTraining.Infrastructure.Messaging.EctoMessageStore
  ← implements Messaging.Ports.MessageStore
  ← persist/1
     list_page/2 (thread_id, cursor params)
     get/1
```

### Phoenix Channel — `ChatChannel`

Added to `UserSocket`:
```elixir
channel "chat:*", MilosTrainingWeb.ChatChannel
```

Topic format: `"chat:thread:{thread_id}"`

**Join:** verifies `current_user` is a participant in the thread; returns `{:error, :forbidden}` otherwise.

#### Client → Server Events

| Event | Behaviour |
|---|---|
| `"send_message"` | Persist + broadcast `"new_message"` to all topic subscribers |
| `"typing_start"` | Broadcast `"typing"` with `%{user_id, typing: true}` |
| `"typing_stop"` | Broadcast `"typing"` with `%{user_id, typing: false}` |
| `"mark_read"` | Update `last_read_message_id` + broadcast `"read_receipt"` |

#### Server → Client Events

| Event | Payload |
|---|---|
| `"new_message"` | `%{id, thread_id, sender_id, sender_nickname, body, message_type, inserted_at}` |
| `"typing"` | `%{user_id, nickname, typing: boolean}` |
| `"read_receipt"` | `%{user_id, last_read_message_id}` |

### Offline Notifier

`MilosTraining.Infrastructure.Messaging.OfflineNotifier` — checks `Phoenix.PubSub.subscribers/2` for the thread topic; dispatches `:chat_message` notification to any participant not currently subscribed.

---

## Section 4 — Interface Layer

### New Controller: `MilosTrainingWeb.MessagingController`

```
GET    /api/threads
         ?context_type=direct|assignment|class_slot
         ?limit, ?cursor
         ← ListThreadsForUser

POST   /api/threads
         body: {participant_id}
         ← GetOrCreateThread (context_type: :direct)

GET    /api/threads/context/:context_type/:context_id
         ← GetOrCreateThread for assignment or class_slot
         ← creates thread + adds both parties as participants on first access

GET    /api/threads/:id/messages
         ?limit, ?cursor
         ← GetThreadMessages

POST   /api/threads/:id/messages
         body: {body, message_type}   ← message_type defaults to :text
         ← SendMessage

POST   /api/threads/:id/read
         body: {last_message_id}
         ← MarkThreadRead
```

All endpoints require `bearerAuth`. Participant membership is enforced by `ThreadPolicy` before any data access.

### Deleted Routes and Controller Actions

```
DELETE  POST /schedule/slots/:id/message             ScheduleController
DELETE  POST /my-workouts/assignments/:id/message     MyWorkoutController
DELETE  GET  /my-workouts/assignments/:id/messages    MyWorkoutController
DELETE  POST /my-workouts/assignments/:id/messages    MyWorkoutController
DELETE  POST /admin/athletes/:id/notes               AdminCoachingController
DELETE  GET  /admin/assigned-workouts/:id/messages   AdminAssignedWorkoutController
```

Corresponding OpenAPI operation specs are removed alongside the actions.

---

## Section 5 — Frontend UI Surfaces

### 5A — Side Panel: Accordion with Details + Conversation

The workout assignment side panel (and class slot side panel) becomes an accordion with two sections. Only one section is open at a time.

```
[📋 Details]                   ▼   ← collapsed
──────────────────────────────────
[💬 Conversation  (3 unread)]  ▲   ← expanded
  ╔══════════════════════════╗
  ║  Good work today! ✓✓    ║  ← sender (right, accent color)
  ╚══════════════════════════╝
     ╔════════════════╗
     ║ Thanks! More?  ║           ← receiver (left, muted color)
     ╚════════════════╝
  Coach (typing…)
──────────────────────────────────
[ Write a message…         Send ]
```

- **Details** is default-open; **Conversation** is default-collapsed
- Unread badge visible on Conversation header even when collapsed
- Clicking a header opens it and closes the other (accordion)
- WhatsApp-style message bubbles: current user on right (accent), others on left (muted)
- New reusable component: `ChatSection` — accepts `contextType`, `contextId`

On mount: `GET /api/threads/context/:type/:id` → join `chat:thread:{id}` Channel → load history.

### 5B — Account Activity → Conversation Chats (read-only history)

Route: `/account/activity/chats` (deep in Settings → Account Activity)

Purpose: historical archive only. No compose capability. Tabs are role-based:

| Role | Tabs |
|---|---|
| Athlete | Direct · Workout |
| Member | Direct · Class |
| Admin / Coach | Direct · Workout · Class |

Thread list → click → expand thread in right panel using `ChatSection` with **input disabled**.

### 5C — TopNav: Messages Icon → Floating Direct Messages Panel

A `MessageSquare` icon in TopNav with an unread badge (aggregates all thread types).

Click → opens a **floating overlay panel** (no page navigation):

```
┌─ Messages ─────────────────────────────── ✕ ┐
│  🔍 Search people…                           │
│  ─────────────────────────────────────────   │
│  🔴 Coach Alex   "Good work today…"  10:32   │
│     Maria K.     "See you Thursday"  Yesterday│
└──────────────────────────────────────────────┘
```

- Search field: finds existing direct threads or users to start a new conversation
- Selecting a thread or a new user → panel transitions to full conversation view (WhatsApp-style, within the same overlay)
- Closing returns to the thread list
- No navigation away from the current page

### 5D — Notification "Messages" Chip

New filter chip `Messages` added to the notification inbox. Filters `type: :chat_message` notifications. No notification is dispatched if the user is already subscribed to the relevant `chat:thread:*` channel topic.

---

## Migration Plan

1. Add `messaging_threads`, `messaging_participants`, `messaging_messages` migrations
2. Add `UNIQUE INDEX ON messaging_threads (context_type, context_id) WHERE context_type != 'direct'`
3. Migrate existing `assignment_messages` rows → Messaging threads/messages (context_type: :assignment)
4. Migrate existing `admin_athlete_notes` rows → Messaging messages (message_type: :coaching_note), auto-creating direct threads per (admin_id, athlete_id) pair
5. Drop `assignment_messages` and `admin_athlete_notes` tables
6. Remove legacy use cases, controller actions, routes, and OpenAPI specs
7. Backfill `Analytics.CommunicationMessage.thread_id` values to reference the newly created `messaging_threads` ids (no formal DB FK exists — it is a plain `binary_id` field)

---

## ADR Reference

This design requires a new ADR covering:
- Introduction of `Messaging` bounded context
- Deprecation of `AssignmentMessage` and `AdminAthleteNote` primitives
- Coaching notes as a message type (visibility change: athletes now see coaching notes)
- `CommunicationMessage` analytics records written as side-effects from Messaging events
- `ChatChannel` added to `UserSocket`
- Accordion UI pattern for side panels
