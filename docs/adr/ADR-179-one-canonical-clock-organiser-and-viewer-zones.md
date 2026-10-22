# ADR-179: One canonical clock, the organiser's zone and the viewer's zone
Date: 2026-10-22
Status: Accepted

## Context
ADR-176 gave each gym a real time zone. Members of the social side can be
anywhere, though, and look at gyms, clubs and events in other countries.
Notifications (trial reminders, event reminders, appointment notices,
missing-WOD alerts, check-in receipts) printed moments as UTC or on a fixed
clock, the web showed every moment on the device's clock, and many "today"
rules (subscriptions, invoices, the classes of today, streaks) read the UTC
day. A moment must mean the same thing to everyone, and read naturally both
to the people who organise it and to people looking from elsewhere.

## Decision
1. **One canonical clock.** Every moment is stored and sent in UTC.
   Conversion happens on demand, at the edge: `Palee.TimeZones.ZonedTime`
   (API) and `src/lib/zoned-time.ts` (web) are the only converters. Both
   resolve DST gaps to just after the jump and repeated times to the first.
2. **The organiser's zone is the primary clock.** A class, an appointment or
   a trial is shown on its gym's zone (`Organizations.organization_timezone`).
   An event uses its own `community_events.time_zone` when it happens
   elsewhere, else its gym's (`Event.time_zone/2`). Event forms show which
   clock they use and let organisers change it; an address hints at it.
3. **The viewer's zone only adds.** The device reports its zone once per
   change (`PUT /api/me/time-zone`, stored on `users.time_zone`; a UTC alias
   never overwrites a real zone). When the viewer's offset at that instant
   differs, the UI names the organiser's city and adds a small "your time"
   badge (`<ZonedTime>`, `<YourTime>`); push texts read
   «24/10 19:00 Athens · 17:00 your time» (`ZonedTime.format_for/5`,
   `Notifications.Domain.PayloadTimes`). Same offset, nothing extra: no
   clutter for the common case.
4. **Push texts are written for each reader.** Payloads carry raw UTC
   moments (`class_starts_at`, `event_starts_at`, `starts_at`, `scanned_at`)
   and, when it differs from the gym's, the organiser's `time_zone`. The
   dispatcher formats them with the reader's locale and zone.
5. **"Today" is the gym's day.** Store code inside a tenant scope asks
   `Tenancy.GymClock.today/0` instead of `Date.utc_today/0`; jobs ask each
   gym's `local_today`. Staff forms (classes, appointment slots) are typed on
   the gym's clock and say so. A person's streak uses their own zone.
   Personal analytics (progress, atlas, daily stats) stay on UTC days for
   now, because their stored buckets are UTC and mixing clocks would be worse.
6. **Gaps are visible and nudged.** API responses carry `time_zone` /
   `timezone_confirmed`; staff see a prompt while their gym's zone is only
   inferred; the vendor console flags active gyms whose zone is not
   confirmed and counts them.

## Consequences
- Moments never drift between screens, pushes and devices; only text differs.
- A new screen that shows a moment must take the organiser's zone and use
  the helpers; a raw `toLocaleString` is a bug.
- Personal analytics on the person's day is follow-up work (re-bucketing).
