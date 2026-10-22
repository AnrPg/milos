"use client";

import { useLayoutEffect, useState, type RefObject } from "react";

import { floatingPosition, type FloatingAlign } from "@/lib/floating-position";

export type FloatingStyle = { left: number; top: number; maxHeight: number } | null;

/**
 * Keeps a fixed-position layer next to its anchor while the page scrolls or
 * resizes, flipping above it when there is no room below. Returns null until
 * the first measurement, so callers render the layer off-screen until then.
 */
export function useAnchoredPosition(
  anchorRef: RefObject<HTMLElement | null>,
  floatingRef: RefObject<HTMLElement | null>,
  { align = "start", width, minWidth = 0, enabled = true }: { align?: FloatingAlign; width?: number; minWidth?: number; enabled?: boolean } = {},
) {
  const [position, setPosition] = useState<FloatingStyle>(null);

  useLayoutEffect(() => {
    if (!enabled) {
      setPosition(null);
      return;
    }
    let frame = 0;
    const update = () => {
      const anchor = anchorRef.current;
      const floating = floatingRef.current;
      if (!anchor || !floating) return;
      const anchorRect = anchor.getBoundingClientRect();
      const viewport = window.visualViewport;
      const next = floatingPosition(
        anchorRect,
        {
          width: width ?? Math.max(minWidth, floating.offsetWidth),
          // scrollHeight is the natural height even while maxHeight clips it.
          height: floating.scrollHeight,
        },
        { width: viewport?.width ?? window.innerWidth, height: viewport?.height ?? window.innerHeight },
        { align, rtl: getComputedStyle(anchor).direction === "rtl" },
      );
      setPosition((current) =>
        current && current.left === next.left && current.top === next.top && current.maxHeight === next.maxHeight
          ? current
          : { left: next.left, top: next.top, maxHeight: next.maxHeight },
      );
    };
    const schedule = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(update);
    };

    update();
    const observer = new ResizeObserver(schedule);
    if (floatingRef.current) observer.observe(floatingRef.current);
    if (anchorRef.current) observer.observe(anchorRef.current);
    window.addEventListener("resize", schedule);
    window.addEventListener("scroll", schedule, true);
    window.visualViewport?.addEventListener("resize", schedule);
    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
      window.removeEventListener("resize", schedule);
      window.removeEventListener("scroll", schedule, true);
      window.visualViewport?.removeEventListener("resize", schedule);
    };
  }, [anchorRef, floatingRef, align, width, minWidth, enabled]);

  return position;
}

/** The caller's own max-height, but never taller than the room on screen. */
export function capHeight(requested: string | number | undefined, room: number | undefined) {
  if (room === undefined) return requested;
  if (requested === undefined) return room;
  return `min(${typeof requested === "number" ? `${requested}px` : requested}, ${room}px)`;
}
