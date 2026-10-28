"use client";

import {
  createContext,
  useContext,
  useEffect,
  useEffectEvent,
  useMemo,
  useRef,
  type CSSProperties,
  type ReactNode,
  type RefObject,
} from "react";
import { createPortal } from "react-dom";

import type { FloatingAlign } from "@/lib/floating-position";

import { capHeight, useAnchoredPosition } from "./floating";

/**
 * One open floating layer and the layers opened from inside it. Every layer
 * renders in its own portal, so a Select inside a popover is not inside the
 * popover's DOM; the tree is what tells the popover that a press on that
 * Select's list is still "inside".
 */
export interface FloatingNode {
  /** The target is in this layer or in a layer opened from it. */
  contains: (target: Node) => boolean;
  /** A layer opened from this one is open, so it owns Escape. */
  hasOpenChild: () => boolean;
  register: (child: FloatingNode) => () => void;
}

const FloatingParentContext = createContext<FloatingNode | null>(null);

/**
 * Joins the floating layer in `ref` to the layer it was opened from, while
 * `enabled`. Render the layer's content inside `<FloatingParent node={node}>`
 * so layers opened from it join it in turn.
 */
export function useFloatingNode(ref: RefObject<HTMLElement | null>, enabled = true): FloatingNode {
  const parent = useContext(FloatingParentContext);
  const children = useRef(new Set<FloatingNode>());
  const node = useMemo<FloatingNode>(
    () => ({
      contains: (target) =>
        Boolean(ref.current?.contains(target)) || [...children.current].some((child) => child.contains(target)),
      hasOpenChild: () => children.current.size > 0,
      register: (child) => {
        children.current.add(child);
        return () => {
          children.current.delete(child);
        };
      },
    }),
    [ref],
  );

  useEffect(() => {
    if (!enabled || !parent) return;
    return parent.register(node);
  }, [enabled, parent, node]);

  return node;
}

export function FloatingParent({ node, children }: { node: FloatingNode; children: ReactNode }) {
  return <FloatingParentContext.Provider value={node}>{children}</FloatingParentContext.Provider>;
}

/**
 * Closes a floating layer on a press outside it and its anchor, and on Escape.
 * Escape is caught before a surrounding dialog sees it, so it closes only the
 * menu, not the dialog the menu was opened from. Pass the layer's `node` so a
 * press inside a layer opened from it (a Select's list, a date picker) does
 * not close it, and Escape closes only the innermost layer.
 */
export function useDismiss(
  refs: ReadonlyArray<RefObject<HTMLElement | null>>,
  onDismiss: (reason: "outside" | "escape") => void,
  enabled = true,
  node?: FloatingNode,
) {
  const dismiss = useEffectEvent(onDismiss);
  const isInside = useEffectEvent(
    (target: Node) => refs.some((ref) => ref.current?.contains(target)) || Boolean(node?.contains(target)),
  );
  const childOwnsEscape = useEffectEvent(() => Boolean(node?.hasOpenChild()));

  useEffect(() => {
    if (!enabled) return;
    const outside = (event: PointerEvent) => {
      const target = event.target as Node | null;
      if (target && isInside(target)) return;
      dismiss("outside");
    };
    const escape = (event: KeyboardEvent) => {
      if (event.key !== "Escape" || childOwnsEscape()) return;
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
  const node = useFloatingNode(floatingRef, open);

  useDismiss(
    [anchorRef, floatingRef],
    (reason) => {
      onClose();
      if (reason === "escape" && restoreFocus) anchorRef.current?.focus();
    },
    open,
    node,
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
      <FloatingParent node={node}>{children}</FloatingParent>
    </div>,
    document.body,
  );
}
