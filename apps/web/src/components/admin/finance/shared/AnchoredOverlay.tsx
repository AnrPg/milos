"use client";

import { useRef, type CSSProperties, type ReactNode, type RefObject } from "react";
import { createPortal } from "react-dom";

import { capHeight, useAnchoredPosition } from "@/components/ui/floating";

/**
 * A ledger dropdown placed next to its trigger on the popover layer. Callers
 * own opening and dismissal; for a self-dismissing menu use ui/Popover.
 */
export function AnchoredOverlay({
  anchorRef,
  children,
  className,
  style,
  minWidth = 200,
  width,
  overlayRef,
}: {
  anchorRef: RefObject<HTMLElement | null>;
  children: ReactNode;
  className?: string;
  style?: CSSProperties;
  minWidth?: number;
  width?: number;
  overlayRef?: RefObject<HTMLDivElement | null>;
}) {
  const internalRef = useRef<HTMLDivElement>(null);
  const targetRef = overlayRef ?? internalRef;
  const position = useAnchoredPosition(anchorRef, targetRef, { width, minWidth });

  if (typeof document === "undefined") return null;

  return createPortal(
    <div
      ref={targetRef}
      className={className}
      style={{
        overflowY: "auto",
        ...style,
        position: "fixed",
        left: position?.left ?? -10_000,
        top: position?.top ?? -10_000,
        maxHeight: capHeight(style?.maxHeight, position?.maxHeight),
        minWidth,
        width,
        zIndex: "var(--z-popover)",
      }}
    >
      {children}
    </div>,
    document.body,
  );
}
