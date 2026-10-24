import type { CSSProperties } from "react";

import type { CardPlacement } from "@/lib/guides/placement";

/** The walkthrough card's box for each placement (lib/guides/placement). */
export function placementClass(placement: CardPlacement) {
  switch (placement.kind) {
    case "sheet":
      return placement.edge === "bottom"
        ? "inset-x-2 bottom-[max(0.5rem,env(safe-area-inset-bottom))] rounded-3xl"
        : "inset-x-2 top-[max(0.5rem,env(safe-area-inset-top))] rounded-3xl";
    case "center":
      return "left-1/2 top-1/2 w-[min(24rem,calc(100vw-2rem))] -translate-x-1/2 -translate-y-1/2 rounded-3xl";
    default:
      return "guide-move w-[22.5rem] rounded-3xl";
  }
}

export function placementStyle(placement: CardPlacement): CSSProperties {
  return placement.kind === "float" ? { left: placement.left, top: placement.top } : {};
}
