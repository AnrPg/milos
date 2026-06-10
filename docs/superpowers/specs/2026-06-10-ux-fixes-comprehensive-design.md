# UX Fixes & Feature Completions — Comprehensive Design Spec
**Date:** 2026-06-10
**Scope:** 16 items (item #8 excluded — handled by separate agent) across schedule, my-workouts, notifications, workout drafts, and UI/roles.
**Implementation strategy:** Cluster B (domain clusters)

---

## Cluster 1 — Panel & Preview System

### Item 1: Full workout preview in schedule/ slot panel

**Problem:** The `AssignedWorkoutPreview` type in `apps/web/src/api/assigned-workouts.ts` does not include `variations` on exercises, so `WorkoutPreviewDetail` renders exercises without scale variations in the my-workouts panel.

**Fix:**
- Add `variations` array to `AssignedWorkoutPreview.exercises` type (matching the shape in `schedule.ts` → `WorkoutPreviewExercise`).
- Backend: verify that the `GetAssignedWorkoutWeek` application service materialises exercises with their variations (same as the schedule path through `WorkoutMaterializer`). If not, update the materialisation query.
- No change needed to `WorkoutPreviewDetail` — it already renders variations correctly when the data is present.

### Item 2: Close button not obscured by TopNav

**Problem:** The side panel `Close ✕` button may be covered by the fixed TopNav bar.

**Fix:**
- Inspect `TopNav` height (approximately `3.5rem` / `56px`).
- In `SlotPopup` and `AssignedWorkoutPanel`, the sticky header already has `top-0`. Change to `top-14` (56px) so the panel header starts below the TopNav.
- Alternatively, wrap the panel container in a `pt-14` div so the scrollable area begins below the nav.
- The backdrop overlay (`fixed inset-0`) is unaffected.

### Item 3: My-workouts cards — click to open panel, remove Preview/Play buttons

**Problem:** Workout cards in `AssignedWorkoutsConsole` still show inline "Preview" and "Play/Start" buttons.

**Fix:**
- Remove the "Preview" and "Play" buttons from the card render.
- The entire card click area calls `setPanelAssignment(assignment)`, opening the `AssignedWorkoutPanel`.
- The panel already has the "Start Workout" CTA at the bottom and full workout detail.
- Admin view: cards show the drag handle (⠿) only; clicking the card body opens the panel.

### Item 5: Schedule info boxes — intuitive labels

**Status:** ✅ Already implemented in `SlotPopup`:
- "Participation approval" with "By coach" / "Auto-confirmed"
- "Deadline to book" with relative + exact datetime

No changes needed.

### Item 6: Workout type color-coding — warm monochromatic palette

**Current state:** `TRAINING_TYPE_COLORS` exists in `SlotPopup` only.

**New palette (same family, clear differentiation):**

| Type | Hex | Description |
|---|---|---|
| crossfit | `#c0392b` | Bold red |
| strength | `#d95d39` | Burnt orange |
| gymnastics | `#c97b4b` | Terracotta |
| aerobics | `#b5651d` | Sandal |
| flexibility | `#8b4513` | Sienna |
| recovery | `#6b3a2a` | Mahogany |

**Propagation:** Extract `TRAINING_TYPE_COLORS` to a shared module (`lib/workout-colors.ts`). Use it in:
- `SlotPopup` (already uses it)
- `AssignedWorkoutPanel` header type label
- Workout cards in `AssignedWorkoutsConsole` (type chip)
- `DragGhostCard`
- `DraggableMonthChip`
- `CalendarView` slot chips (if applicable)

---

## Cluster 2 — Athlete Workout Management

### Item 7: Withdraw pending booking → hard-delete admin notification

**Problem:** When an athlete cancels a pending booking, the `booking_pending` notification remains in the admin's inbox.

**Fix:**
- Backend: in the `CancelBooking` application service (or the booking status transition handler), after successfully cancelling, call `Notifications.delete_notifications_for_booking(booking_id)`.
- This function queries notifications where `payload->>'booking_id' = booking_id` AND `type = 'booking_pending'` and hard-deletes them.
- This ensures the admin's inbox is clean — the request was never acted on.
- Frontend: no change needed; the cancel flow already calls `onCancelBooking → onClose`.

### Item 10: Athlete drag-and-drop (enable for all users) + "Reschedule" in panel

**Problem:** DnD in `AssignedWorkoutsConsole` is `disabled: !isAdmin` — athletes cannot drag workouts.

**Fix — DnD:**
- Change `disabled: !isAdmin` → `disabled: false` in both `DraggableCard` and `DraggableMonthChip`.
- The drag handle (⠿) is shown for all users (currently only shown when `isAdmin`). Show it for all.
- In `handleDragEnd`: add a past-date guard — if `destinationDate < todayIso`, do nothing (no API call, no state update).
- On successful drop: admins call `updateAssignedWorkout` (existing `/admin/assigned-workouts/:id` PATCH). Athletes call a **new endpoint** `PATCH /my-workouts/assignments/:id/reschedule` with `{ scheduled_for: string }`. Both paths trigger the `workout_moved` notification.

**Fix — Reschedule form in `AssignedWorkoutPanel`:**
- Add a "Reschedule" button below the workout preview section.
- On click: reveals an inline form with `<input type="date" min={todayIso}>`.
- Submit: admins call `updateAssignedWorkout`; athletes call the new `rescheduleAssignment` API function → on success, panel calls `onClose` and parent refreshes the calendar.
- Backend: extend the `workout_moved` notification to include: athlete nickname, workout title, original date, new date, context URL `/my-workouts?open_assignment=<id>`.

**Backend — `workout_moved` notification:**
- New notification type: `workout_moved`
- Payload: `{ athlete_nickname, workout_title, from_date, to_date, assignment_id, url }`
- Delivered to all admin users.
- Triggered when `UpdateAssignedWorkout` (admin path) or the new `RescheduleAssignedWorkout` (athlete path) application service is called.
- Backend controller: new action `reschedule` in `MyWorkoutController`, guarded by athlete token. Validates `scheduled_for >= today`. Updates the assignment date and fires `workout_moved` event.

---

## Cluster 3 — Notification System

### Item 4: Message to coach in workout previews

**Status:** ✅ Already implemented:
- `SlotPopup` has "Message your coach" section (non-admin only).
- `AssignedWorkoutPanel` has "Message your coach" section (non-admin only).

No changes needed.

### Item 9: Notification click → redirect + open panel + mark read

**Current state:** Click → `markRead` + `router.push(url)`. The URL in payload is generic (e.g. `/my-workouts`, `/schedule`).

**Fix:**
- Backend: when creating notifications that reference a specific resource, include the resource ID in the URL:
  - Booking notifications: `/schedule?open_slot=<slot_id>`
  - Assigned workout notifications: `/my-workouts?open_assignment=<assignment_id>`
  - Workout moved notifications: `/admin/coaching-assignments?open_assignment=<assignment_id>`
- Frontend — `ScheduleConsole`: on mount, read `searchParams.get('open_slot')`. If present, find the slot in the fetched data and call `setSelectedSlot(slot)` to open the `SlotPopup`.
- Frontend — `AssignedWorkoutsConsole`: on mount, read `searchParams.get('open_assignment')`. If present, find the assignment and call `setPanelAssignment(assignment)`.
- The `NotificationBell` `handleNotificationClick` already handles mark-read + navigate — no change needed there.

### Item 12: Differentiate "workout deleted" vs "workout changed" notifications

**Current state:** `notificationTitle` already distinguishes `workout_changed` and `workout_deleted`. The gap is in backend payload content.

**Fix:**
- `workout_changed` backend payload: include `change_type` field — `"sections_updated"` or `"datetime_changed"`.
- `workout_deleted` backend payload: clear message in `body` field: `"Coach deleted this workout from your schedule."`.
- Frontend `notificationBody` for `workout_changed`: if `change_type === "datetime_changed"` → "The scheduled time for this workout was changed." If `"sections_updated"` → "Some exercises or sections in this workout were updated."
- Frontend `notificationTitle` for `workout_deleted` → rename to "Workout deleted by coach" for clarity.

### Item 15: Auto-mark-as-read when browser push is enabled

**Design:**
- When a push notification is delivered to the service worker, the push payload includes the `notification_id`.
- In the service worker `push` event handler (in `public/sw.js` or equivalent), after showing the notification, call the API `PATCH /notifications/<id>/read` using a stored token (from IndexedDB or the push subscription context).
- If the API call is not feasible from the service worker context, fallback: the `usePushNotifications` hook listens for the `notificationclick` event and marks the notification read when the user interacts with it.
- In `NotificationBell`, when the panel opens, notifications that were delivered via push (identifiable by a flag in payload or simply by checking if `read_at` is already set server-side) appear in the "Read" section.

---

## Cluster 4 — Workout Edit & Drafts

### Item 13: Warning modal for editing published workout

**Status:** ✅ Already fully implemented in `WorkoutEditModal`:
- 3 options: Cancel / Proceed to edit globally / Duplicate and edit for this context only.
- Triggered from both `SlotPopup` ("Edit workout" button) and `AssignedWorkoutPanel` ("Edit workout" button).

No changes needed.

### Item 14: Draft autosave — one draft per in-progress workout, cleanup on publish

**Desired behaviour:**
1. New workout → `createDraftWorkout` → 1 new draft record. All subsequent autosaves PATCH the same draft by ID.
2. Continue editing → user selects an existing draft from the list → opens with `?draft=<id>` → autosaves PATCH that same ID.
3. Publish → status changes to `published`. Backend deletes any orphan draft records for the same admin that were created during a reopen flow.
4. Workout list → shows published workouts + any unpublished drafts (naturally one per in-progress creation if autosave is correctly PATCHing).

**What to fix:**
- **Audit autosave in `WorkoutCreationCanvas`**: verify the canvas always holds the current `draftId` in state and calls `updateDraftWorkout(draftId, ...)` (PATCH). If any autosave path calls `createDraftWorkout` again, fix it to PATCH.
- **Backend `publishWorkout`**: after publishing, hard delete any other draft records with `status = 'draft'` that share the same `reopened_from_id` (the original workout ID, if tracking reopen lineage). This cleans up the draft created by `reopenWorkout` after the edited version is published.
- **Frontend list**: no filtering needed — if backend returns one draft per in-progress workout and published workouts, the list is correct. Drafts show "Continue editing" button; published show normal actions.

---

## Cluster 5 — UI & Roles

### Item 16: URL renames + role-aware headings

**New routes:**

| Role | Old URL | New URL | Page Title |
|---|---|---|---|
| Admin | `/admin/schedule` (if exists) | `/admin/class-schedule` | "Class Schedule" |
| Admin | `/my-workouts` (admin view) | `/admin/coaching-assignments` | "Coaching Assignments" |
| Athlete | `/schedule` | `/schedule` | "Schedule" (unchanged) |
| Athlete | `/my-workouts` | `/my-workouts` | "My Workouts" (unchanged) |

**Changes:**
- New pages: `apps/web/src/app/admin/class-schedule/page.tsx` (wraps `ScheduleConsole` with `roles={["admin"]}`) and `apps/web/src/app/admin/coaching-assignments/page.tsx` (wraps `AssignedWorkoutsConsole`).
- `TopNav`: admin sees links "Class Schedule" → `/admin/class-schedule` and "Coaching Assignments" → `/admin/coaching-assignments`. Athlete sees "Schedule" → `/schedule` and "My Workouts" → `/my-workouts`.
- `ScheduleConsole` and `AssignedWorkoutsConsole`: accept a `pageTitle` prop (or infer from role) to render the correct heading.
- Old routes (`/admin/schedule`) get a `redirect()` to the new URL for backwards compatibility.

### Item 17: UI style uniformity + login default tab + gamification help icons

**Login default tab:**
- In `AuthConsole`, change `useState<Mode>("register")` → `useState<Mode>("login")`.

**UI style uniformity:**
- Audit `landing-page.tsx` and `auth-console.tsx` against the design system: background `#0A0A0F`, surfaces `#111118` / `#0d0d18`, text `#F0EDF8` / `#8888aa`, accent `#d95d39`.
- Apply consistent card borders (`border: "1px solid #1a1a28"`), border-radius (`rounded-[1.5rem]` or `rounded-[2rem]`), and typography scale.

**Gamification help icons:**
- Each metric/graph card on the landing page gets a `?` icon button (top-right corner of the card).
- **Hover behaviour:** CSS tooltip (`title` attribute or a lightweight `<span>` tooltip) showing a 1-line description.
- **Click behaviour:** Opens an `InfoModal` component (new shared component) that renders:
  - Title: what this metric is called
  - What it measures
  - How it's calculated
  - What a good score means
  - How to improve it
- `InfoModal` is a shared component at `components/InfoModal.tsx`, styled consistently with the dark design system.
- The gamification elements (streaks, leaderboard, challenge badges, volume chart) are styled with vibrant, motivating colours — use the existing `#d95d39` accent plus complementary warm tones (`#d9ab4e` for gold/achievements, `#4db89c` for streaks/completions).

---

## Cross-cutting

- All new notification types (`workout_moved`, updated payloads for `workout_changed`/`workout_deleted`) must be handled in `notificationTitle` and `notificationBody` in `NotificationBell.tsx`.
- All new URLs added to `TopNav` must be role-gated.
- After all changes: `mix format`, `mix test`, `mix credo --strict` on backend. `tsc --noEmit` on frontend.
