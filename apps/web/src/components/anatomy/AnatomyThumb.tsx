"use client";

import { useEffect, useRef, useState } from "react";

import { highlightsKey, paletteKey, type AnatomyHighlights, type AnatomyView } from "@/lib/anatomy/figure";

import { useAnatomyLabel, useAnatomyPalette } from "./use-anatomy-environment";

export type AnatomyThumbProps = {
  highlights: AnatomyHighlights;
  view?: AnatomyView;
  /** CSS pixels; width follows the view (½ height per figure). Default 64. */
  height?: number;
  className?: string;
};

/**
 * A cheap static anatomy thumbnail for lists and cards. It starts rendering
 * when it scrolls near the viewport; all thumbnails share one offscreen WebGL
 * context and a cache of PNG data URLs keyed by highlight set, view, size and
 * theme colours, so many cards never create many contexts.
 */
export function AnatomyThumb({ highlights, view = "front", height = 64, className = "" }: AnatomyThumbProps) {
  const label = useAnatomyLabel(highlights);
  const palette = useAnatomyPalette();
  const ref = useRef<HTMLSpanElement>(null);
  const [visible, setVisible] = useState(false);
  const [result, setResult] = useState<{ key: string; src: string | null }>({ key: "", src: null });
  const width = Math.round(view === "both" ? height : height / 2);
  const key = `${view}|${height}|${paletteKey(palette)}|${highlightsKey(highlights)}`;

  useEffect(() => {
    const element = ref.current;
    if (!element) return;
    if (typeof IntersectionObserver === "undefined") {
      queueMicrotask(() => setVisible(true));
      return;
    }
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          setVisible(true);
          observer.disconnect();
        }
      },
      { rootMargin: "200px" },
    );
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  const latest = useRef({ highlights, view, width, height, palette });
  useEffect(() => {
    latest.current = { highlights, view, width, height, palette };
  });

  useEffect(() => {
    if (!visible) return;
    let cancelled = false;
    import("@/lib/anatomy/renderer/thumbs")
      .then(({ renderThumb }) => renderThumb(latest.current))
      .then((src) => {
        if (!cancelled) setResult({ key, src });
      })
      .catch(() => {
        if (!cancelled) setResult({ key, src: null });
      });
    return () => {
      cancelled = true;
    };
  }, [key, visible]);

  const src = result.key === key ? result.src : null;

  return (
    <span
      ref={ref}
      role="img"
      aria-label={label}
      className={`inline-block shrink-0 ${className}`}
      style={{ width, height }}
      data-anatomy-thumb={src ? "ready" : "pending"}
    >
      {src ? (
        // eslint-disable-next-line @next/next/no-img-element -- a generated data URL; next/image adds nothing here.
        <img src={src} alt="" aria-hidden="true" width={width} height={height} className="block h-full w-full" />
      ) : (
        <span aria-hidden="true" className="block h-full w-full rounded-full bg-[var(--panel-raised)] opacity-60" />
      )}
    </span>
  );
}
