# ADR-274: Unsaved edits, the save bar and undo/redo on staff forms
Date: 2026-10-29
Status: Proposed (option A of the save-bar mockups; awaiting ANR's pick)

## Context
On a person's profile (admin/users/[id]), the Finance tab saved fields one by
one: the status on select, the dates when the date picker closed. The date
save ran inside the picker's close handler with the draft from the render
before the pick, so the PATCH re-sent the old date and nothing changed.
There was no visible save, cancel, undo or redo, and switching tabs or
collapsing a panel dropped anything typed.

## Decision
- Staff forms keep a draft apart from the server copy (`lib/draft-history`):
  whole-draft undo/redo steps (capped at 100), discard, commit, and rebase
  when the server copy changes (untouched fields follow the server, edited
  ones keep their edit).
- `ui/SaveBar` appears only while something changed: «N αλλαγές χωρίς
  αποθήκευση», Αναίρεση, Επανάληψη, «Ακύρωση», «Αποθήκευση». It sticks to
  the bottom of its panel, says «Οι αλλαγές αποθηκεύτηκαν.» once after a
  save and shows errors in place. Ctrl/⌘+S saves; Ctrl/⌘+Z and
  Ctrl/⌘+Shift+Z (Ctrl+Y) undo/redo outside text fields.
- `ui/UnsavedChanges`: forms register; the page calls `guard(action)` before
  anything that unmounts them (tab switch, section links) and asks «Μένω
  εδώ» / «Απόρριψη» / «Αποθήκευση». Closing or reloading the browser tab
  gets the browser's warning.
- Edited fields show «● Αλλαγμένο». Saves send only the changed fields.
- Actions with their own confirmed step (freezes, leaving the box,
  allowance extensions and revocations) stay outside the bar.
- Profile panels hide their content instead of unmounting it.

## Rationale
One explicit save for several fields, no accidental writes to finance data,
and no extra click to start editing; the bar is absent when there is nothing
to save, which keeps the screen quiet.

## Alternatives Considered
- Save on every change with an «Αναίρεση» toast: writes each intermediate
  value to finance records and the ledger audit trail.
- A read-only tab with an «Επεξεργασία» button: one more click for every
  edit, and two modes to understand.

## Consequences
New staff forms with plain field edits use the draft history and SaveBar
instead of save-on-blur. The Finance tab's automatic-renewal switches are
part of the draft and are saved with the bar.

## Implementation Notes
`components/admin/users/membership-draft.ts` maps the membership and its
renewable packages to a draft and to the calls a save makes (one PATCH, one
renewal call per changed switch). A save inside the minimum commitment still
asks for a reason (ADR-097) before it goes through.
