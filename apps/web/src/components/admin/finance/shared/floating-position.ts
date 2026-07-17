export type RectLike = Pick<DOMRect, "left" | "right" | "top" | "bottom" | "width" | "height">;

type Size = { width: number; height: number };
type Viewport = { width: number; height: number };

const VIEWPORT_GAP = 16;
const TRIGGER_GAP = 8;

export function floatingPosition(anchor: RectLike, overlay: Size, viewport: Viewport) {
  const roomBelow = viewport.height - anchor.bottom - VIEWPORT_GAP;
  const roomAbove = anchor.top - VIEWPORT_GAP;
  const placement = roomBelow >= overlay.height || roomBelow >= roomAbove ? "bottom" : "top";
  const unclampedTop =
    placement === "bottom"
      ? anchor.bottom + TRIGGER_GAP
      : anchor.top - overlay.height - TRIGGER_GAP;

  return {
    placement,
    left: Math.min(
      Math.max(anchor.left, VIEWPORT_GAP),
      Math.max(VIEWPORT_GAP, viewport.width - overlay.width - VIEWPORT_GAP),
    ),
    top: Math.min(
      Math.max(unclampedTop, VIEWPORT_GAP),
      Math.max(VIEWPORT_GAP, viewport.height - overlay.height - VIEWPORT_GAP),
    ),
  } as const;
}
