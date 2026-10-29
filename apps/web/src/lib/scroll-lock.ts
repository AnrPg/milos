/**
 * One page-scroll lock shared by every overlay (ui/Dialog, viewers, the
 * camera, the full-page filter page). Each open overlay holds a lock; the
 * page scrolls again only when the last one is released, whatever order they
 * close in.
 *
 * Overlays used to save `body.style.overflow` on open and put it back on
 * close. When two were open and the outer one closed first (a dialog that
 * opens another and then closes itself, or a parent unmounting before its
 * child), the inner one "restored" the `hidden` it had seen on open and the
 * page stayed frozen until a reload, while the nav bars still answered taps.
 */

const holders = new Set<symbol>();
let saved: string | null = null;

/** Locks page scrolling until the returned release runs (idempotent). */
export function lockPageScroll(): () => void {
  const id = Symbol("scroll-lock");
  if (holders.size === 0) {
    saved = document.body.style.overflow;
    document.body.style.overflow = "hidden";
  }
  holders.add(id);
  return () => {
    if (!holders.delete(id) || holders.size > 0) return;
    document.body.style.overflow = saved ?? "";
    saved = null;
  };
}

/** How many overlays hold the lock now (tests and diagnostics). */
export function pageScrollLocks(): number {
  return holders.size;
}
