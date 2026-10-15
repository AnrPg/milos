"use client";

import { useEffect, useRef, useState } from "react";

/** Counts from 0 up to `target` with an ease-out curve. */
export function useCountUp(target: number, durationMs = 1200): number {
  const [value, setValue] = useState(0);
  const rafRef = useRef<number | null>(null);
  const startTimeRef = useRef<number | null>(null);

  useEffect(() => {
    if (target === 0) {
      queueMicrotask(() => setValue(0));
      return;
    }

    startTimeRef.current = null;
    const easeOutQuart = (t: number) => 1 - Math.pow(1 - t, 4);

    function step(ts: number) {
      if (!startTimeRef.current) startTimeRef.current = ts;
      const progress = Math.min((ts - startTimeRef.current) / durationMs, 1);
      setValue(Math.round(easeOutQuart(progress) * target));
      if (progress < 1) rafRef.current = requestAnimationFrame(step);
    }

    rafRef.current = requestAnimationFrame(step);
    return () => {
      if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
    };
  }, [target, durationMs]);

  return value;
}
