"use client";

import { useEffect, useEffectEvent, useRef } from "react";

import { lockPageScroll } from "@/lib/scroll-lock";

const FOCUSABLE = [
  "a[href]",
  "button:not([disabled])",
  "input:not([disabled])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  "[tabindex]:not([tabindex='-1'])",
].join(",");

/**
 * Open dialogs, innermost last: only the innermost one answers Escape and
 * Tab, so closing a sheet opened from compose leaves compose open.
 */
const openDialogs: symbol[] = [];

export function useModalFocusTrap<T extends HTMLElement>(onClose: () => void) {
  const dialogRef = useRef<T>(null);
  const close = useEffectEvent(onClose);

  useEffect(() => {
    const dialog = dialogRef.current;
    const id = Symbol("dialog");
    openDialogs.push(id);
    const previouslyFocused = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const releaseScroll = lockPageScroll();

    const focusable = () => Array.from(dialog?.querySelectorAll<HTMLElement>(FOCUSABLE) ?? []);
    // A field marked data-autofocus (a picker's search box) wins; otherwise
    // the first control of the content, not the header's × (data-dialog-close),
    // which stays one Shift+Tab away. A field that focused itself on mount
    // (React autoFocus) keeps focus.
    if (!dialog?.contains(document.activeElement)) {
      const controls = focusable();
      (
        dialog?.querySelector<HTMLElement>("[data-autofocus]") ??
        controls.find((element) => !element.hasAttribute("data-dialog-close")) ??
        controls[0] ??
        dialog
      )?.focus();
    }

    const handleKeyDown = (event: KeyboardEvent) => {
      if (openDialogs[openDialogs.length - 1] !== id) return;
      if (event.key === "Escape") {
        event.preventDefault();
        close();
        return;
      }

      if (event.key !== "Tab") return;
      const elements = focusable();
      if (elements.length === 0) {
        event.preventDefault();
        dialog?.focus();
        return;
      }

      const first = elements[0];
      const last = elements[elements.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };

    document.addEventListener("keydown", handleKeyDown);
    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      openDialogs.splice(openDialogs.indexOf(id), 1);
      releaseScroll();
      previouslyFocused?.focus();
    };
  }, []);

  return dialogRef;
}
