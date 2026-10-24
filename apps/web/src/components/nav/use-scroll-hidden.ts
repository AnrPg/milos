"use client";

import { useEffect, useRef, useState } from "react";

import { nextScrollHidden } from "@/lib/bottom-nav";

function prefersReducedMotion() {
  return typeof window !== "undefined" && typeof window.matchMedia === "function" && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

/**
 * Instagram-like: the member app's bars slide away while scrolling down and
 * return on any scroll up or near the top. Not with reduced motion. A new
 * page always starts with them shown. The bottom bar and the top bar each
 * call it and so move together.
 */
export function useScrollHidden(enabled: boolean, pathname: string) {
  // The page it was hidden on; another page shows it again.
  const [hiddenOn, setHiddenOn] = useState<string | null>(null);
  const state = useRef({ hidden: false, lastY: 0 });

  useEffect(() => {
    state.current = { hidden: false, lastY: window.scrollY };
    if (!enabled || prefersReducedMotion()) return;
    let frame = 0;
    const onScroll = () => {
      if (frame) return;
      frame = window.requestAnimationFrame(() => {
        frame = 0;
        const y = window.scrollY;
        const next = nextScrollHidden(state.current, y);
        if (Math.abs(y - state.current.lastY) >= 8 || next !== state.current.hidden) state.current.lastY = y;
        if (next !== state.current.hidden) {
          state.current.hidden = next;
          setHiddenOn(next ? pathname : null);
        }
      });
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      window.removeEventListener("scroll", onScroll);
      if (frame) window.cancelAnimationFrame(frame);
    };
  }, [enabled, pathname]);

  const reveal = () => {
    state.current.hidden = false;
    setHiddenOn(null);
  };
  return [enabled && hiddenOn === pathname, reveal] as const;
}
