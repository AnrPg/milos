# ADR-199: Notification preferences per category and channel
Date: 2026-10-24
Status: Accepted

## Context
Vision §7.11 lists «notifications» under Εγώ › Ρυθμίσεις and the mockup's
`settings` screen shows one switch per category (bookings, messages, clubs,
water reminder). The app had only a per-device push on/off, hidden in the
Security card, and nothing per category on the web or in the API. About a
hundred notification types are written from many places
(`Palee.Notifications.process_event/2`, booking notices, password recovery,
the wellness and buddy jobs), so a check per sender would miss some.

## Decision
1. **Categories live in one domain module.**
   `Notifications.Domain.NotificationCategories` lists the categories in
   display order: `bookings`, `messages`, `community`, `coach`, `partners`,
   `journal`, `staff`, `account`. Each one names its types, its channels, and
   whether it is `locked`. Each one also has an `audience` (`everyone` or
   `staff`). A unit test checks that every type in
   `Notification.types/0` has exactly one category and that no category
   names a type that does not exist.
2. **Channels.** The channels are `in_app` (the bell) and `push` (web push
   and store-app push, ADR-171). `email` is a known channel, but no category
   has it yet: today's only emails (owner invitations, corporate invoices)
   go to people outside the app. A push is built from the bell row, so a
   push goes out only while the category's bell is on. The API reports
   `push: false` while `in_app` is off, and the stored push choice comes
   back when the bell is turned on again.
3. **Storage.** The `notification_preferences` table holds one row per
   (user, category, channel). A row is written only when the person changes
   a switch. With no row, the channel is on, which is how notifications
   worked before this ADR. Categories are strings checked by the domain, so
   a new category needs no migration. The table is personal data with
   owner-only RLS and is listed in the tenancy audit.
4. **Two checks, one per channel, both at the existing chokepoints.**
   `CreateNotification` writes every bell row and checks `in_app`: a muted
   notification is `{:ok, :suppressed}`, the same as ADR-184's demo
   suppression, so nothing is written or pushed. `DispatchNotification`
   queues every push and checks `push`. Both use
   `Queries.DeliversNotification`. If the choices cannot be read, the
   notification is delivered.
5. **Locked: account and payments.** Security, invoices, payment reminders,
   expiring packages and subscriptions, ended access, journal exports and
   shop orders are always delivered. The API refuses to change them (422
   `locked_category`), and Settings shows «Πάντα ενεργές».
6. **API.** `GET /api/notifications/preferences` returns every category with
   its resolved channels. `PUT /api/notifications/preferences/:category`
   takes `{in_app?, push?}` and returns the whole list.
7. **Web.** Ρυθμίσεις has a «Ειδοποιήσεις» card (`#notifications`). The card
   holds push on this device first (`PushDeviceCard`), then one row per
   category with an «Στην εφαρμογή» switch and a «Push» switch. The push
   control and its permission flow moved here from Security. The bell
   shares the same card and shows it while push is off. Only staff see the
   `staff` row. The clubs row links to Τα box και τα clubs μου, where each
   club's level is set (unchanged).
8. **Deep links into Settings.** A bell notification that links to a section
   of the page already open (same path, different `#hash`) now opens that
   section, because Next's navigation does not fire `hashchange`.
   `password_reset_completed` now opens `/me/settings#security`.

## Rationale
- One map plus two chokepoints means a new type cannot slip through. The
  exhaustiveness test fails until the new type has a category.
- Storing only the switches people change keeps today's behaviour for
  everyone and keeps the table small. It also means a default can change
  later without a backfill.
- A category is coarse enough to fit on one phone screen. Per-club levels
  and per-filter alerts already exist where those objects live (vision §4.1,
  one home per object).

## Alternatives Considered
- **A per-type matrix.** It has about a hundred switches, so it is too much
  for a person to manage.
- **Checks in each sender.** Senders would be missed, and nothing could test
  that every type is covered.
- **Muting the bell by writing rows as already read.** The rows would stay
  in the list, and the push would be sent anyway.
- **A column per channel.** Every new channel would need a migration.

## Consequences
- A new notification type must be added to a category, and the unit test
  enforces it.
- The wellness `water_reminder` preference still decides whether water
  reminders are made at all. The `journal` category decides whether they
  are delivered.
- Push jobs queued before a change are still sent.
- When an email channel arrives, it is added to a category's `channels`,
  the check runs in that email sender, and the UI adds a column.

## Implementation Notes
- Migration `20261219100000_create_notification_preferences`.
- `Notification.types/0` is now public, so the map can be tested.
