# ADR-222: Class booking rules say what they do; no-limit approval wait; cancellation cutoff in minutes
Date: 2026-10-28
Status: Accepted

## Context
ANR found the class defaults confusing. «Προεπιλεγμένο χρονικό όριο κράτησης (λεπτά)»
(`booking_timeout_minutes`) read like a booking deadline, and was easy to mix up with
«Άνοιγμα κρατήσεων» (`booking_window_days`). It is neither: for a class without automatic
confirmation, it is how long a pending request waits for staff before it is cancelled
(`BookingTimeoutJob`). The member popup made it worse by showing it as «Κράτηση από 1h πριν
από την έναρξη», a cutoff the server never enforced. ANR also wanted a «Χωρίς όριο» choice
and the late-cancellation cutoff entered as hours plus minutes.

## Decision
1. `booking_timeout_minutes` (gym default, class, recurring class) is nullable. null = no
   limit: the request waits until the class starts. Every request's deadline is
   `min(now + timeout, class start)` (`BookingPolicy.approval_deadline/3`), counted from the
   moment the request becomes pending, so a promoted waitlist entry gets the full time.
2. The gym default late-cancellation cutoff is stored in minutes:
   `scheduling_settings.default_cancellation_cutoff_hours` becomes
   `default_cancellation_cutoff_minutes` (0–10080, null = always free; migration
   20261228100000 multiplies existing values by 60). Packages keep whole hours
   (`booking.cancellation_cutoff_hours`); `BookingTerms` turns them into minutes, so
   `BookingPolicy.late_cancellation?/4` and `AppointmentPolicy.late_cancellation?/3` take
   minutes.
3. Every field of «Προεπιλογές δημιουργίας τμήματος» has a descriptive label and a help line
   (namespace `BookingRules`). Durations are entered as hours + minutes
   (`DurationLimitField`, `lib/duration-parts.ts`) and read in words (`formatMinutes`).
4. The class popup shows «Χρόνος απάντησης» to staff and «Απαιτεί έγκριση · απάντηση μέσα σε …»
   to members. Bookings stay open until the class starts, as the server already enforced.

## Rationale
Minutes are the smallest unit staff asked for, and one integer keeps validation, the API and
the policy simple. Capping the wait at the class start removes requests that could never be
answered usefully and makes «Χωρίς όριο» safe.

## Alternatives Considered
- A real "bookings close X before the start" rule to match the old popup text: a new rule
  nobody asked for; can be added later as its own field.
- Moving package cutoffs to minutes too: touches stored package JSON and the package editor;
  left for when ANR asks.

## Consequences
- API: `default_cancellation_cutoff_hours` is gone from `/admin/settings`; clients send
  `default_cancellation_cutoff_minutes`. `booking_timeout_minutes` may be null in requests.
- The old `Ui` keys of the section (`featureDefaultBookingTimeout`, `admCancellationCutoffHours`,
  …) are unused; they are left in the catalogs so the parallel translation rewrite merges
  cleanly, and can be deleted afterwards.
