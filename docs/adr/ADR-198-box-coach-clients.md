# ADR-198: Box › «Πελάτες μου», the coach's home in the member app
Date: 2026-10-24
Status: Accepted

## Context
Vision §6.2 and §7.10 put the coach's daily work in the same app:
`Box › Πελάτες μου` (reply queue, form-review queue, check-in desk, clients).
Until now a coach had only the web console (`/admin`), so a coach who used
the member app had no place there for their clients. The console already
has every piece: the reply queue, the form-review queue and its feedback
form, "My clients" and class and appointment attendance endpoints. One
piece was missing: the staff schedule roster did not say who had checked
in, so no screen could show attendance per person. The class attendance
endpoint also read a `:current_user` assign that no plug sets, so every
call crashed.

## Decision
1. **A Box extension, not a third layout.** `CoachClientsBoxExtension` is
   one entry in `box-extensions.tsx` (ADR-170) for both gym and coach
   layouts. It renders only when the selected membership holds the `coach`
   role. A solo coach is owner and coach, so the same check covers both.
2. **Four parts, each hidden when empty, and the whole section hidden when
   all are empty** (vision §4.2):
   - *Περιμένουν απάντηση*: the staff reply queue (`GET /staff/reply-queue`),
     sorted by urgency. A row opens the thread (`/me/activity/chats?thread=`),
     the same route the console uses. There is no unified-inbox coach filter
     on `main` yet; when it lands, only `chatThreadHref` changes.
   - *Αξιολόγηση τεχνικής*: submitted form reviews. A row opens a sheet with
     the video, the athlete's note and the console's own `ReviewForm`
     (exported, not copied). Both screens share the `["staff", "form-reviews"]`
     query keys, so an answer in one refreshes the other.
   - *Check-in σήμερα*: today's classes the coach leads and their personal
     sessions, in the gym's time zone, without sessions nobody booked. A row
     opens the roster with «Ήρθε» / «Δεν ήρθε». Classes write through
     `POST /admin/schedule/slots/:slot_id/attendance/:user_id` (`run_classes`)
     and sessions through `POST /staff/appointments/:id/attendance`
     (`manage_appointments`). The class list reuses Box's own schedule query.
   - *Πελάτες*: the coach's coaching relationships as chips. Each chip opens
     the client's console profile (`/admin/users/:id`), which stays the one
     home of a client.
   Queues show five rows, then point to the console for the rest.
3. **The staff roster carries attendance.** `GetScheduleCalendar` adds
   `attendance_status` to every booking it returns to staff. The value comes
   from a new port call, `Scheduling.list_class_attendance/2`, which returns
   `{slot_id, user_id} => status`. A guest seat has none of its own. Members
   still receive no roster.
4. **Fix:** the class attendance action takes the staff member from
   `Guardian.Plug.current_resource/1` and reads path params in either key form.

## Rationale
The extension point keeps `BoxHub` and both layouts untouched. Reusing the
staff endpoints and the console's form means no second implementation to
keep in step. Putting attendance on the existing roster payload costs one
indexed query per schedule read by staff, and it also serves the console's
class sheet later.

## Alternatives Considered
- *A new `/staff/coach-desk` aggregate endpoint.* Rejected: every part already
  has an endpoint, and an aggregate would duplicate their scoping rules.
- *Embedding the console panels (`ReplyQueue`, `FormReviewQueue`,
  `MyClientsSection`) as they are.* Rejected: they carry console chrome
  (status filters, take-an-athlete search) that clutters a phone card.
- *Linking the desk to the console's class schedule.* Rejected: the console
  has no per-person attendance screen today.

## Consequences
- Chips and «see all» links open console pages, so they switch the app to
  the console view (ADR-103).
- `AdminRecordAttendance` checks the branch (ADR-186) but not that a
  coach whose rights are scoped to their own clients leads the class.
  Tightening that is follow-up work for the scheduling services.
- Programming, coach notes, nutrition editing and class-timer control
  (vision §7.10) stay in the console for now.
