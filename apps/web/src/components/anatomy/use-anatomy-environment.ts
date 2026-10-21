"use client";

import { useMemo, useSyncExternalStore } from "react";
import { useFormatter, useTranslations } from "next-intl";

import {
  DEFAULT_ANATOMY_PALETTE,
  highlightsByRole,
  paletteKey,
  readAnatomyPalette,
  type AnatomyHighlights,
  type AnatomyPalette,
} from "@/lib/anatomy/figure";

// The theme provider rewrites <html>'s data-theme and inline CSS variables.
function subscribeTheme(onChange: () => void) {
  const observer = new MutationObserver(onChange);
  observer.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme", "style", "class"] });
  return () => observer.disconnect();
}

let lastPalette: AnatomyPalette = DEFAULT_ANATOMY_PALETTE;
function paletteSnapshot(): AnatomyPalette {
  const next = readAnatomyPalette();
  if (paletteKey(next) !== paletteKey(lastPalette)) lastPalette = next;
  return lastPalette;
}

/** The figure's colours from the current theme's CSS tokens; updates when the theme changes. */
export function useAnatomyPalette(): AnatomyPalette {
  return useSyncExternalStore(subscribeTheme, paletteSnapshot, () => DEFAULT_ANATOMY_PALETTE);
}

const REDUCED_MOTION = "(prefers-reduced-motion: reduce)";

function subscribeMotion(onChange: () => void) {
  if (typeof window.matchMedia !== "function") return () => undefined;
  const query = window.matchMedia(REDUCED_MOTION);
  query.addEventListener("change", onChange);
  return () => query.removeEventListener("change", onChange);
}

export function usePrefersReducedMotion(): boolean {
  return useSyncExternalStore(
    subscribeMotion,
    () => typeof window.matchMedia === "function" && window.matchMedia(REDUCED_MOTION).matches,
    () => false,
  );
}

/** Text alternative: the highlighted muscles, by role, in the member's language. */
export function useAnatomyLabel(highlights: AnatomyHighlights): string {
  const t = useTranslations("Anatomy");
  const format = useFormatter();
  return useMemo(() => {
    const parts = highlightsByRole(highlights).map(([role, ids]) =>
      t("figure.roleList", {
        role: t(`role.${role}`),
        muscles: format.list(ids.map((id) => t(`muscle.${id}`))),
      }),
    );
    return t("figure.summary", { details: parts.length > 0 ? parts.join(" ") : t("figure.none") });
  }, [format, highlights, t]);
}
