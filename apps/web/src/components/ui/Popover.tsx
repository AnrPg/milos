"use client";

import { useEffect, useEffectEvent, useRef, type CSSProperties, type ReactNode, type RefObject } from "react";
import { createPortal } from "react-dom";

import type { FloatingAlign } from "@/lib/floating-position";

import { capHeight, useAnchoredPosition } from "./floating";

/**
 * Closes a floating layer on a press outside it and its anchor, and on Escape.
 * Escape is caught before a surrounding dialog sees it, so it closes only the
 * menu, not the dialog the menu was opened from.
 */
export function useDismiss(
  refs: ReadonlyArray<RefObject<HTMLElement | null>>,
  onDismiss: (reason: "outside" | "escape") => void,
  enabled = true,
) {
  const dismiss = useEffectEvent(onDismiss);
  const isInside = useEffectEvent((target: Node) => refs.some((ref) => ref.current?.contains(target)));

  useEffect(() => {
    if (!enabled) return;
    const outside = (event: PointerEvent) => {
      const target = event.target as Node | null;
      if (target && isInside(target)) return;
      dismiss("outside");
    };
    const escape = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      event.stopPropagation();
      dismiss("escape");
    };
    document.addEventListener("pointerdown", outside);
    window.addEventListener("keydown", escape, true);
    return () => {
      document.removeEventListener("pointerdown", outside);
      window.removeEventListener("keydown", escape, true);
    };
  }, [enabled]);
}

/**
 * A menu, dropdown or picker anchored to a trigger. It renders through a
 * portal on the popover layer (--z-popover), so no card, sticky bar, sheet or
 * clipping ancestor can cover it, flips above the trigger near the bottom of
 * the screen and scrolls inside itself when the screen is short.
 */
export function Popover({
  anchorRef,
  open,
  onClose,
  children,
  align = "start",
  width,
  minWidth,
  className = "",
  style,
  role,
  id,
  ariaLabel,
  restoreFocus = true,
}: {
  anchorRef: RefObject<HTMLElement | null>;
  open: boolean;
  onClose: () => void;
  children: ReactNode;
  align?: FloatingAlign;
  /** Fixed width in px; otherwise the content's width (at least minWidth). */
  width?: number;
  minWidth?: number;
  className?: string;
  style?: CSSProperties;
  role?: "menu" | "listbox" | "dialog";
  id?: string;
  ariaLabel?: string;
  /** Send focus back to the trigger after Escape. */
  restoreFocus?: boolean;
}) {
  const floatingRef = useRef<HTMLDivElement>(null);
  const position = useAnchoredPosition(anchorRef, floatingRef, { align, width, minWidth, enabled: open });

  useDismiss(
    [anchorRef, floatingRef],
    (reason) => {
      onClose();
      if (reason === "escape" && restoreFocus) anchorRef.current?.focus();
    },
    open,
  );

  if (!open || typeof document === "undefined") return null;

  return createPortal(
    <div
      ref={floatingRef}
      id={id}
      role={role}
      aria-label={ariaLabel}
      className={`overflow-y-auto overscroll-contain ${className}`}
      style={{
        ...style,
        position: "fixed",
        left: position?.left ?? -10_000,
        top: position?.top ?? -10_000,
        maxHeight: capHeight(style?.maxHeight, position?.maxHeight),
        width,
        minWidth,
        maxWidth: "calc(100vw - 1rem)",
        zIndex: "var(--z-popover)",
        visibility: position ? undefined : "hidden",
      }}
    >
      {children}
    </div>,
    document.body,
  );
}
