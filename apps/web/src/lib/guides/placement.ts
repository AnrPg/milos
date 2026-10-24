import type { RectLike } from "@/lib/floating-position";

/**
 * Where a walkthrough card goes (ADR-193), never over the spot it explains:
 * - phones: a sheet on the bottom edge, or the top edge when the spot is in
 *   the lower half;
 * - wider screens: beside the spot (below, above, then the end side, then
 *   the start side), else the bottom corner when the spot fills the screen;
 * - no spot: the middle of the screen.
 */
export type CardPlacement =
  | { kind: "center" }
  | { kind: "sheet"; edge: "top" | "bottom" }
  | { kind: "float"; left: number; top: number };

type Size = { width: number; height: number };

export const PHONE_MAX_WIDTH = 640;
const GAP = 12;
const MARGIN = 16;

export function cardPlacement(spot: RectLike | null, card: Size, viewport: Size, rtl = false): CardPlacement {
  if (!spot) return { kind: "center" };
  if (viewport.width < PHONE_MAX_WIDTH) {
    const middle = spot.top + spot.height / 2;
    return { kind: "sheet", edge: middle > viewport.height / 2 ? "top" : "bottom" };
  }

  const clampLeft = (left: number) => Math.min(Math.max(left, MARGIN), Math.max(MARGIN, viewport.width - card.width - MARGIN));
  const clampTop = (top: number) => Math.min(Math.max(top, MARGIN), Math.max(MARGIN, viewport.height - card.height - MARGIN));
  const alignedLeft = clampLeft(rtl ? spot.right - card.width : spot.left);

  if (viewport.height - spot.bottom - GAP - MARGIN >= card.height) return { kind: "float", left: alignedLeft, top: spot.bottom + GAP };
  if (spot.top - GAP - MARGIN >= card.height) return { kind: "float", left: alignedLeft, top: spot.top - GAP - card.height };

  const roomEnd = rtl ? spot.left - GAP - MARGIN : viewport.width - spot.right - GAP - MARGIN;
  const roomStart = rtl ? viewport.width - spot.right - GAP - MARGIN : spot.left - GAP - MARGIN;
  const besideTop = clampTop(spot.top);
  if (roomEnd >= card.width) return { kind: "float", left: rtl ? spot.left - GAP - card.width : spot.right + GAP, top: besideTop };
  if (roomStart >= card.width) return { kind: "float", left: rtl ? spot.right + GAP : spot.left - GAP - card.width, top: besideTop };

  return {
    kind: "float",
    left: clampLeft(rtl ? MARGIN : viewport.width - card.width - MARGIN),
    top: clampTop(viewport.height - card.height - MARGIN),
  };
}

/** The highlighted hole: the spot with some air, kept on screen. */
export function spotlightRect(spot: RectLike, viewport: Size, padding = 6) {
  const left = Math.max(spot.left - padding, 2);
  const top = Math.max(spot.top - padding, 2);
  const right = Math.min(spot.right + padding, viewport.width - 2);
  const bottom = Math.min(spot.bottom + padding, viewport.height - 2);
  return { left, top, width: Math.max(right - left, 0), height: Math.max(bottom - top, 0) };
}

/** The dimmed layer: the whole screen with the spot cut out (even-odd fill). */
export function scrimPath(viewport: Size, spot: { left: number; top: number; width: number; height: number } | null, radius = 16) {
  const outer = ["M0 0", `H${viewport.width}`, `V${viewport.height}`, "H0", "Z"].join(" ");
  if (!spot) return outer;
  const { left: x, top: y, width, height } = spot;
  const r = Math.min(radius, width / 2, height / 2);
  return [
    outer,
    `M${x + r} ${y}`,
    `H${x + width - r}`,
    `A${r} ${r} 0 0 1 ${x + width} ${y + r}`,
    `V${y + height - r}`,
    `A${r} ${r} 0 0 1 ${x + width - r} ${y + height}`,
    `H${x + r}`,
    `A${r} ${r} 0 0 1 ${x} ${y + height - r}`,
    `V${y + r}`,
    `A${r} ${r} 0 0 1 ${x + r} ${y}`,
    "Z",
  ].join(" ");
}
