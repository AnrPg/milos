# ADR-182: Themed dropdowns and date and time pickers instead of native controls
Date: 2026-10-22
Status: Accepted

## Context
ANR reported (2026-10-22, phone screenshots) that dropdowns and the date picker
look like "old Windows" and run off the screen on phones: the Users filters, the
season editor's package and programme day pickers, and the date fields. These
were native `<select>` and `<input type="date|time|datetime-local">` controls.
The browser draws their popups itself, so `color-scheme` and `accent-color` only
tint them: the list colours, fonts, scrollbars and position are the platform's,
and a desktop Chrome popup can be wider than a narrow window. The theme rule
(docs/brand/THEME.md) asks for every part of every control to follow the theme.

## Decision
- `components/ui/Select` replaces every native select. It takes `<option>` and
  `<optgroup>` children like a native select, reports `onValueChange(value)`,
  and opens its list in `ui/Popover` (ADR-177): portalled, kept inside the
  viewport, flipped above the trigger near the bottom of the screen, scrolling
  inside itself, every colour from theme tokens. It is a WAI-ARIA combobox with
  a listbox (arrow keys, Home/End, Page keys, typeahead, Escape). `name` adds a
  hidden input and `required` a hidden validated input, so forms keep working.
- `components/ui/DateInput`, `TimeInput` and `DateTimeInput` replace date, time
  and datetime-local inputs. Values keep the native formats, so callers and APIs
  are unchanged. The calendar uses the viewer's locale for month and weekday
  names and its first day of the week, has month and year views for far dates,
  honours `min`/`max`, and offers Today and (for optional fields) Clear. Time is
  two 24-hour columns, stepped by `step`.
- `ui/native-controls-guard.test.ts` fails on a native select or date/time input
  anywhere in the web sources.
- The Dialog focus trap now gives initial focus to the first control of the
  content rather than the header ×, so a sheet opens ready to use.
- Spark gains a "go-now" role (`SPARK_GO_STYLE`): Check in, Start/Resume
  workout, Join a club, group or channel. Save, submit and confirm stay Dojo.

## Rationale
A themed control built on the existing popover primitive fixes both complaints
(theme and overflow) at the root, app-wide, and the guard keeps them from coming
back. Keeping native option markup and value formats made the switch mechanical
(a TypeScript AST codemod over 82 files), with no API or data changes.

## Alternatives Considered
- Styling native controls further: impossible for the popup itself.
- A third-party select/date library (Radix, react-day-picker): another styling
  system and dependency for what two small components over ui/Popover do.
- A `{ target: { value } }` shim for `onChange`: less clear than a value
  callback, and would keep event-shaped code where there is no event.

## Consequences
- Tests drive selects by clicking the trigger and an option. Unit tests use
  `ui/select-test-utils` (`chooseOption`, `chooseValue`); e2e tests use
  `e2e/support/select.ts` (`chooseOption`, `chooseDate`). The trigger exposes
  its value as `data-value`.
- Mobile users lose the OS wheel pickers; the themed pickers are touch-sized
  (44 px rows and day cells).

## Implementation Notes
- New translations: the `Pickers` namespace in all 12 locales.
- `Segmented` (package wizard) now delegates to `SegmentPicker`, so billing
  periods are one row, a full grid or a dropdown, never a wrapped row.
