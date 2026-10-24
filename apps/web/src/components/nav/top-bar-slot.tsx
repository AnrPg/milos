"use client";

import { useSyncExternalStore, type ReactNode } from "react";
import { createPortal } from "react-dom";

// The member top bar's action slot, next to the bell. A page puts its own
// action there (the Feed's ⊕ new post, vision §4 principle 3) with
// <TopBarActions>; without a top bar the action stays in the page.

let slot: HTMLElement | null = null;
const listeners = new Set<() => void>();

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

/** The ref MemberTopBar gives its slot element. */
export function registerTopBarSlot(element: HTMLElement | null) {
  if (slot === element) return;
  slot = element;
  listeners.forEach((listener) => listener());
}

export function TopBarActions({ children }: { children: ReactNode }) {
  const element = useSyncExternalStore(
    subscribe,
    () => slot,
    () => null,
  );
  if (element) return createPortal(children, element);
  return <div className="flex justify-end gap-2">{children}</div>;
}
