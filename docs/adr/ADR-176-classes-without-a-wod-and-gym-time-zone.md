# ADR-176: Classes without a WOD, and the gym's time zone
Date: 2026-10-22
Status: Accepted

## Context
Staff who can create classes want to schedule a class before its WOD exists
and link the WOD later. Until then the class must read as incomplete, must
not be published to members, and staff must be told why. Series are the
exception: a series may run without a WOD (each class gets its WOD day by
day), but a class still without one on its own day is flagged from 00:00 and
the staff concerned are alerted at 07:00 that morning and one hour before it
starts.

"00:00" and "07:00" are the gym's local time. The gym's zone existed
(`organization_settings.timezone`) but only the vendor could edit it, its
default `UTC` could not be told apart from a real choice, and many rules read
the UTC day instead.

## Decision
1. **Readiness is derived, not stored.** `Scheduling.Domain.ClassWorkoutReadiness`
   decides from `master_workout_id` and `class_series_id`:
   * `published?/1`: a class with a WOD or in a series. A standalone class
     without one is a **draft**.
   * `workout_status/3`: `linked`, `awaiting` (series class before its day),
     `missing` (draft, or series class from 00:00 on its day; the badge).
   * `alert_moments/2` and `alert_due/3`: 07:00 local on the day (only while
     earlier than the hour-before alert) and one hour before. A sweep sends
     the latest moment already passed, so a missed sweep never sends a stale
     morning alert after the hour-before one.
2. **Drafts are invisible by default.** `list_slots_window` drops drafts
   unless the caller passes `include_drafts: true` (only the staff schedule
   and the staff calendar feed do), so a new member-facing caller cannot leak
   one. Booking is refused with `class_not_published` in `BookingPolicy`
   (book, waitlist, guest) and again in the store under the slot lock (trials,
   staff placement). A class someone booked cannot lose its WOD.
3. **Linking** is `PUT /admin/schedule/slots/:id/workout` (`LinkClassWorkout`,
   capabilities `manage_schedule` or `manage_workouts`). The WOD is filed in the
   day's Classes folder like any class edit. Series accept `master_workout_id: null`.
4. **Alerts** (`class_workout_missing`): `ClassWorkoutAlertsJob` every five
   minutes runs `ClassWorkoutAlerts.sweep/2` per gym over classes without a
   WOD starting within 24 h (partial index
   `scheduled_classes_missing_workout_index`). Recipients: members with
   `manage_schedule` and the class's coach. The dedupe key
   `class_workout_missing:<class>:<alert>:<start>` makes overlapping sweeps
   and retries harmless; a moved class owes new alerts. Drafts alert too (they
   are invisible to members, which matters even more on the day).
5. **The gym's time zone is first-class.** `organization_settings.timezone_source`
   is `confirmed` (an admin or the vendor set it), `inferred` (a guess) or
   null (never set). `Organizations.Domain.TimeZonePolicy` resolves the zone
   (`organization_timezone/1`, `local_today/2`), and a guess never replaces a
   confirmed zone (decided under a row lock). Admins confirm it in Settings
   (`PUT /admin/settings/time-zone`); "Set your time zone" is the first
   onboarding step for gyms and coaches, cannot be skipped, and marking it
   done confirms the current zone. While unconfirmed, an owner's or admin's
   device reports its browser zone once per session as the guess; if it has
   none, an IP-derived zone header from the edge (`cf-timezone`,
   `x-vercel-ip-timezone`, `cloudfront-viewer-time-zone`) is used. With
   nothing known, `:default_organization_timezone` (Europe/Athens) applies.
   Existing gyms whose zone is not UTC are migrated as confirmed.

## Rationale
Deriving readiness keeps one source of truth (the WOD link) with no state to
drift. Filtering in the store by default is safer than filtering in each
member use case. A sweep plus dedupe keys survives restarts, WOD links and
time changes without scheduling and cancelling per-class jobs. The browser's
zone is more accurate than IP geolocation (VPNs, mobile carriers) and needs no
GeoIP database or third-party lookup of staff IPs; IP is the fallback when the
edge provides it.

## Alternatives Considered
* A `status` column (draft/published) on classes: duplicates the WOD link and
  can disagree with it.
* One Oban job per class per alert: must be rescheduled on every edit, link
  and time change.
* Calling an external IP-geolocation API: sends staff IPs to a third party.
* Using the series' own `timezone` for alerts: series are created from the
  editor's device; the gym's zone is the rule ANR set.

## Consequences
* `organization_timezone/1` no longer falls back to UTC; gyms that never set a
  zone run on the default until a guess or confirmation arrives.
* About 95 call sites still read `Date.utc_today()`; those that mean "the
  gym's day" move to `Organizations.local_today/2` in a follow-up, and finance's
  separate `entitlement_timezone` should follow the gym's zone.

## Implementation Notes
* Migrations `20261130100000_classes_without_a_wod` (notification type,
  partial index) and `20261130110000_organization_timezone_source`.
* Staff see the "Draft · no WOD" / "No WOD" badge on calendar cards and a
  notice with an inline WOD picker in the class sheet.
