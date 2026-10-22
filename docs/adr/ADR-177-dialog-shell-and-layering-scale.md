# ADR-177: One dialog shell, one popover primitive and a z-index scale
Date: 2026-10-22
Status: Accepted

## Context
On phones, "Create series" and most other overlays grew taller than the
screen: they did not scroll, and their save, cancel and close buttons fell
below the fold, so the dialog could not be finished or dismissed. About 60
modals, sheets and drawers were each hand-built (`fixed inset-0`, their own
max-height, padding and focus handling), several with `max-h-[90vh]` (which
ignores the mobile browser bars) or no cap at all.

The top-nav account (kebab) menu and other dropdowns were absolutely
positioned inside their trigger's stacking context (the sticky nav is
`z-50`), so any later element with a higher z-index, or an `overflow`
ancestor, covered or clipped them. Z-indexes were literals from 10 to 9999
with no shared order.

## Decision
- **Layering scale** in `globals.css`: `--z-raised` 10, `--z-sticky` 30,
  `--z-nav` 50, `--z-drawer` 60, `--z-modal` 70, `--z-fullscreen` 80,
  `--z-popover` 90, `--z-toast` 100, used as `z-(--z-modal)`. Popovers sit
  above modals because menus open from inside dialogs.
- **`ui/Dialog`**: the only modal shell. It portals into `<body>`, caps the
  panel to the dynamic viewport (`fixed inset-0` + `max-h-full`, safe-area
  insets, `interactive-widget=resizes-content` so the keyboard shrinks it),
  keeps the header and footer fixed while only the body scrolls, traps focus,
  closes on Escape, the × button and a press that starts and ends on the
  backdrop, and can be a `<form>` (`onSubmit`). Variants: `center`, `sheet`
  (bottom sheet on phones), `drawer` (end edge), `panel` (sheet on phones,
  drawer from `md`). `dismissible={false}` while saving; `bare` and
  `plainBody` for screens that own their layout.
- **`ui/Popover`**: the only dropdown primitive. It portals onto
  `--z-popover`, positions with `lib/floating-position` (flips above the
  trigger, clamps to the viewport, `maxHeight` = room left, so it scrolls
  inside itself), follows scroll and resize, and closes on an outside press
  or Escape without closing the dialog it was opened from.
- **`ui/Layer`** portals full-screen surfaces (photo and media viewers,
  camera, full-page pickers) that keep their own layout.
- `components/ui/layering-guard.test.ts` fails on literal z-indexes above 10
  and on `fixed inset-*-0` layers without a scale token.

## Rationale
Fixing each screen would leave the next new dialog to repeat the bug. One
shell makes "actions always reachable on a small screen" a property of the
component, and the guard keeps new code on the scale.

## Alternatives Considered
- Native `<dialog>` with the top layer: solves stacking but not the
  scrolling body and sticky footer, and nested popovers inside it would
  still need their own top-layer handling; browser support for styling the
  backdrop with theme variables is uneven in the store webviews.
- A third-party headless library (Radix, Floating UI): adds a dependency
  for what is ~300 lines here, and the existing focus trap already handles
  nested dialogs.

## Consequences
- Every overlay now covers the nav (drawers used to start below it).
- Dialogs portal out of their React parent's DOM; styles that relied on an
  ancestor (rare) must move onto the dialog.
- `hooks/useModalFocusTrap` also honours `data-autofocus` and a field that
  focused itself (React `autoFocus`).

## Implementation Notes
- `lib/floating-position.ts` moved from `admin/finance/shared`; finance
  `AnchoredOverlay` now uses the shared positioning hook.
- `community/Sheet`, finance `SidePanel`, `InfoModal` and `WellnessSheet`
  keep their APIs and render through `Dialog`.
- `scripts/check-hardcoded-ui-copy.mjs` treats the shell's class and style
  props as technical.
