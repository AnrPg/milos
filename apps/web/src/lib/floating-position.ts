export type RectLike = Pick<DOMRect, "left" | "right" | "top" | "bottom" | "width" | "height">;

type Size = { width: number; height: number };
type Viewport = { width: number; height: number };

export type FloatingAlign = "start" | "end";

export type FloatingOptions = {
  /** Which anchor edge the overlay lines up with, in reading direction. */
  align?: FloatingAlign;
  /** Right-to-left layouts mirror the alignment. */
  rtl?: boolean;
};

const TRIGGER_GAP = 8;

/** Phones keep a narrower margin to the screen edge than desktops. */
function viewportGap(viewport: Viewport) {
  return viewport.width < 480 ? 8 : 16;
}

/**
 * Where a floating layer (menu, popover, picker) goes next to its anchor:
 * below it when it fits or there is more room there, otherwise above, always
 * inside the viewport. `maxHeight` is the room left on the chosen side, so a
 * tall menu scrolls inside itself instead of running off a small screen.
 */
export function floatingPosition(anchor: RectLike, overlay: Size, viewport: Viewport, options: FloatingOptions = {}) {
  const gap = viewportGap(viewport);
  const roomBelow = viewport.height - anchor.bottom - gap - TRIGGER_GAP;
  const roomAbove = anchor.top - gap - TRIGGER_GAP;
  const placement = roomBelow >= overlay.height || roomBelow >= roomAbove ? "bottom" : "top";
  const maxHeight = Math.max(0, Math.floor(placement === "bottom" ? roomBelow : roomAbove));
  const height = Math.min(overlay.height, maxHeight);
  const unclampedTop =
    placement === "bottom" ? anchor.bottom + TRIGGER_GAP : anchor.top - height - TRIGGER_GAP;

  const alignEnd = (options.align ?? "start") === "end" ? !options.rtl : Boolean(options.rtl);
  const width = Math.min(overlay.width, viewport.width - gap * 2);
  const unclampedLeft = alignEnd ? anchor.right - width : anchor.left;

  return {
    placement,
    maxHeight,
    left: Math.min(Math.max(unclampedLeft, gap), Math.max(gap, viewport.width - width - gap)),
    top: Math.min(Math.max(unclampedTop, gap), Math.max(gap, viewport.height - height - gap)),
  } as const;
}
