# ADR-290: Rooms on the floor plan in classes, room photos, a visual cleaning checklist, machine log photos and pins
Date: 2026-10-30
Status: Accepted (extends ADR-202)

## Context
ADR-202 gave each branch floor plans with its spaces drawn on them, used by
the cleaning staff's «Σήμερα» list. Machines only recorded how many stand in
which space, and a class showed its space as a plain chip. ANR asked
(2026-10-30, thread "Check box floor plan uploads") for:
- the room of a class shown coloured on the floor plan, from the class
  details only (never on the schedule cards), when the gym turns it on;
- photos of each room, to get an idea of it;
- a visual cleaning checklist: owners, admins and front desk add photos of
  the parts of a room and what to clean there; the janitor answers each one;
- photos on the machine log, and the plan with a pin where the machine stands.
The mockup (https://claude.ai/artifact/1j8y7gGBE23JypBSJTx5LZ) settled the
options: A on every screen, plus B's pin map under a machine's log.

## Decision
- **The gym's switch.** `space_settings.floor_plans_in_classes` (one row per
  gym, off by default, owners and admins: `manage_spaces`). With more than one
  floor in a branch, each floor can stay out (`space_floor_plans.shown_in_classes`,
  on by default); the per-floor switches show only then.
- **The room of a class.** `GET /api/org/:slug/schedule/slots/:id/space`
  (`ClassRoom`) returns the space (name, description, directions), the floor
  plan and area, and the room photos. Staff who see the spaces always get
  them; everyone else only with the switch on, and the plan only when its
  floor is shown (`PhotoPolicy.class_view/3`). Drafts stay staff-only. The
  schedule's `space` carries `viewable`, so the chip in the class details
  becomes «📍 Χώρος · Δες στην κάτοψη» only when there is something to show.
  Cleaning points never show here.
- **Room photos and cleaning points are two lists**, `space_photos` and
  `space_cleaning_points`, so a close-up made for the janitor never reaches
  members by mistake. Up to 30 each per room, ordered, private tenant media
  (`space_photo`, `cleaning_photo`) read through signed URLs. Owners, admins
  and front desk manage both (`manage_spaces` or `edit_space_details`).
- **Public page.** A room photo starts off the public box page; whoever
  uploads turns it on per photo with a subtle floating 🌐 that hides again
  after a moment. The public page lists the rooms that have public photos.
- **The janitor's carousel.** Finishing a cleaning in a room with points
  needs an answer for every point: `cleaned` or `not_cleaned`, a note
  required for `not_cleaned`, an optional "after" photo. The answers are kept
  on the entry (`housekeeping_entries.point_results`) with the point's
  instruction and photo as they were, so the log still reads right after the
  point changes. Each point left not cleaned notifies whoever reviews the
  cleaning log (`cleaning_point_not_cleaned`, front desk by default), with
  the notes.
- **Machine log photos**: up to 10 per log line (`media_ids`, `machine_photo`).
- **Machine pins**: a placement row may pin its items on its space's floor
  plan (`positions`, `[x, y]` within 0..1, at most one per item placed
  there; `space_not_on_plan` when the space is not drawn). The machine's log
  returns `places`; under the log the plan shows the room (red while the
  machine is out of order) with its pins. There is no map of all machines.

## Consequences
- Migration `20270331100000`: three tenant tables with RLS, two columns,
  three media purposes and one notification type (constraints rewritten from
  their current definition so other branches' additions stay).
- New error codes: `space_photos_full`, `invalid_point_results`,
  `cleaning_point_unanswered`, `cleaning_point_note_required`,
  `invalid_machine_position`, `space_not_on_plan`, `too_many_machine_photos`.
- `GET /machines/:id/events` now returns `{events, places}`.
