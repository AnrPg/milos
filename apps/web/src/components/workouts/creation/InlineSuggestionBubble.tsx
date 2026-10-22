"use client";

import type { Editor } from "@tiptap/react";
import { useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";

import { useUiTranslations } from "@/i18n/ui";
import { useDismiss } from "@/components/ui/Popover";

import type { MarkClick } from "./assistant-highlights";

const GAP = 8;
const MARGIN = 8;

/**
 * The assistant's suggestions for clicked words (ADR-181), opened in place:
 * right above the words, or below them when there is no room above. Several
 * overlapping suggestions are listed one under the other.
 */
export function InlineSuggestionBubble({
  editor,
  click,
  onClose,
  children,
}: {
  editor: Editor;
  click: MarkClick;
  onClose: () => void;
  children: ReactNode;
}) {
  const i18n = useUiTranslations();
  const ref = useRef<HTMLDivElement>(null);
  const [position, setPosition] = useState<{ top: number; left: number } | null>(null);

  useDismiss([ref], onClose);

  useLayoutEffect(() => {
    const place = () => {
      const bubble = ref.current;
      if (!bubble || editor.isDestroyed) return;
      const size = editor.state.doc.content.size;
      const start = editor.view.coordsAtPos(Math.min(click.from, size));
      const end = editor.view.coordsAtPos(Math.min(click.to, size));
      const wordsTop = Math.min(start.top, end.top);
      const wordsBottom = Math.max(start.bottom, end.bottom);
      const { width, height } = bubble.getBoundingClientRect();
      const fitsAbove = wordsTop - GAP - height >= MARGIN;
      const top = fitsAbove ? wordsTop - GAP - height : Math.min(wordsBottom + GAP, window.innerHeight - height - MARGIN);
      const left = Math.min(Math.max(start.left, MARGIN), window.innerWidth - width - MARGIN);
      setPosition({ top: Math.max(top, MARGIN), left: Math.max(left, MARGIN) });
    };
    place();
    window.addEventListener("resize", place);
    window.addEventListener("scroll", place, true);
    const observer = typeof ResizeObserver === "undefined" ? null : new ResizeObserver(place);
    if (ref.current) observer?.observe(ref.current);
    return () => {
      window.removeEventListener("resize", place);
      window.removeEventListener("scroll", place, true);
      observer?.disconnect();
    };
  }, [editor, click]);

  return createPortal(
    <div
      ref={ref}
      role="dialog"
      aria-label={i18n("assistantSuggestionsHere")}
      className="fixed max-h-[60vh] w-[min(24rem,calc(100vw-1rem))] space-y-2 overflow-y-auto rounded-2xl p-2 shadow-xl"
      style={{
        zIndex: "var(--z-popover)",
        top: position?.top ?? -9999,
        left: position?.left ?? -9999,
        visibility: position ? "visible" : "hidden",
        background: "var(--panel)",
        border: "1px solid var(--border)",
      }}
    >
      {children}
    </div>,
    document.body,
  );
}
