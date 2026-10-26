# ADR-202: Spaces, floor plans, class spaces, the cleaning schedule and machine placement
Date: 2026-10-26
Status: Accepted

## Context
A box has rooms and areas: the main floor, a second studio, the showers, the cardio corner.
Before this ADR these existed in three disconnected places:
- the cleaning log had its own «areas» (`housekeeping_areas`, ADR-102), with no branch;
- a class only knew its branch (`location_id`, ADR-097 and ADR-186);
- a machine (ADR-104) only knew how many the box owns, not where they stand.

So nobody could see that two classes were booked into the same room, close a room for repairs, give
the cleaning staff a schedule, or tell where the six treadmills are.

## Decision
1. **Space («Χώρος», `spaces`).**
   - A room or area of one branch, or of the whole gym when `location_id` is null.
   - It has a name, a description, directions («Πώς θα φτάσεις»), the cleaning checklist (`tasks`) and an archive date.
   - It is a new context, `Palee.Spaces`, with port `SpaceStore`, an Ecto adapter, and TenantDataPolicy purge order 105.
2. **Cleaning areas become spaces.**
   - Migration `20261222100000` renames `housekeeping_areas` to `spaces` in place: pkey, indexes, FK, trigger and RLS policy.
   - Ids are kept, so every `housekeeping_entries.area_id` still points at the same row.
   - The cleaning API is unchanged on the wire. `/staff/cleaning/areas*` now reads and writes spaces through `Application.CleaningLog`, and the entries keep `area_id`.
3. **Floor plan («Κάτοψη», `space_floor_plans`).**
   - One image per floor, several per branch.
   - Uploaded with the media pipeline: new purpose `floor_plan`, private, 8 MB, inspected. Like box photos, the media is marked attached when the plan is created.
   - A space may sit on one plan and carry an `area`, a polygon of 3–32 points in normalized 0..1 coordinates (origin top-left). The editor draws rectangles by dragging.
   - Deleting a plan clears `floor_plan_id` and `area` on its spaces.
4. **Unavailability (`space_unavailabilities`).**
   - Windows from–to with a reason.
   - A class that would take place in a space while it is unavailable is refused with 409 `space_unavailable`. This covers create, create-many, a series (every expanded occurrence) and an edit at any series scope.
   - Making a space unavailable never moves classes. The answer lists `affected_classes` so the desk can move them.
5. **Class space (`space_id`).**
   - On `scheduled_classes` and `class_series`. Composite FKs with ON DELETE SET NULL; occurrences copy it from their series; it is a shared field of series edits.
   - The space must be active and must fit the class's branch: its own branch, or a gym-wide space. The current space of an edited class stays valid even after it is archived.
   - The schedule payload returns `space_id` and `space {id, name}` to everyone. For staff it also returns `space_overlap`, when another class overlaps in the same space, and `space_unavailable`.
   - Overlap is a warning flag, not a block.
6. **Cleaning schedule (`housekeeping_schedules`).**
   - One per space: ISO weekdays, times (HH:MM, at most 12) and a comment.
   - `GET /staff/cleaning/today` lists what is due today on the gym clock. The number of cleanings due is the number of times, or 1 when no times are set; it is counted against the entries finished today.
   - It also returns the caller's open entries and the floor plans.
   - The cleaning staff tap a space on the plan to start it, or use a plain list when it is on no plan. Start and finish are the ADR-102 flow.
7. **Machine placement (`inventory_machine_placements`).**
   - Rows of (machine_id, space_id, quantity > 0), one per space.
   - `PUT /staff/inventory/machines/:id/placements` replaces the whole placement. It locks the machine row, so the placed total never exceeds the quantity owned (`placement_exceeds_quantity`).
   - A machine's quantity cannot be lowered below what is placed. The rest shows as `unassigned`.
   - Each space's detail lists its equipment.
8. **Rights.**
   - `manage_spaces`: owner and admin. Grantable to front desk per gym (ADR-120 role access).
   - `edit_space_details` (name, description, directions only) and `set_space_unavailable`: front desk.
   - `view_spaces`: coach and front desk; owner and admin have it implicitly.
   - `manage_cleaning_schedule`: owner, admin and front desk.
   - Whoever can edit a class can set its space. Placement uses the inventory or spaces rights. Reading spaces is also open to `manage_schedule`.
   - Branch-scoped staff (ADR-186) see and change only their branches' spaces and floor plans, like every other located item. Gym-wide spaces (no branch) are for staff of every branch.

## Rationale
- **Renaming instead of copying** keeps every entry id valid without a data rewrite, and keeps the old API working untouched for the apps already in the field.
- **Normalized polygon coordinates** survive any image size or zoom. Storing rectangles as four points keeps the door open for free polygons later.
- **Overlap as a warning:**
  - open-gym and semi-private sessions often share a floor on purpose, so an overlap is shown, not blocked;
  - a closure is a hard fact, so it is a block.
- **Placement as rows** fits interchangeable items ("Treadmill × 6"), and the check runs in the same transaction as the write.

## Alternatives Considered
- **Spaces inside `Palee.Facility` (branches).** Rejected: facility is about the public branch profile, and spaces carry cleaning, schedule and inventory links. A separate context keeps the purge order and the ports clear.
- **A new `spaces` table plus a copy of the areas.** Rejected: it doubles the data during rollout and forces an id remap of `housekeeping_entries`.
- **Blocking overlapping classes.** Rejected for the reason above; the flag is enough for the planner.
- **A `space_id` column on machines.** Rejected: one machine row stands for several items that can stand in several rooms.

## Consequences
- **Cleaning.** `manage_cleaning_areas` still creates and archives cleaning areas from the cleaning log; these are spaces now.
- **Greek wording.** «Χώρος» now means a space. The branch strings that said «Χώρος» now say «Παράρτημα», as the ontology proposed.
- **Media.** The tenant media purpose check accepts `floor_plan`.
- **Purge order.** Spaces purge after scheduling and inventory, and before facility.

## Implementation Notes
- **Domain.** `Spaces.Domain.SpacePolicy` holds the editable field sets, the area rules, the window, overlap and availability checks, and the branch fit.
- **Housekeeping.** `Housekeeping.Domain.CleaningSchedule` normalizes the schedule and builds the due list.
- **Inventory.** `Inventory.Domain.PlacementPolicy` merges and validates placement rows.
- **Orchestration.** It lives in Application modules: `ClassSpace` (checks and the schedule annotation), `SpaceDirectory` (settings, detail, floor plans), `CleaningLog` and `PlaceMachine`.
- **Web.**
  - `/admin/spaces` (`SpacesSettings`), linked from Settings › Παραρτήματα and from a dashboard tile.
  - `SlotSpaceSelect` next to the branch select in both class editors.
  - The space chip and warnings in `SlotPopup`.
  - `CleaningToday` and `CleaningSchedules` on the cleaning log.
  - `MachinePlacement` in the machine row.
- **Tests.**
  - Domain unit tests.
  - Controller tests for CRUD and rights per role, grants, branch scope, floor plans, the unavailable refusal (single and series), the overlap flag, the cleaning schedule and Today, and placement.
  - A migration down/up test with data.
  - Vitest for the floor plan geometry and the Today logic.
  - Playwright specs in `apps/web/e2e/spaces.spec.ts`.
