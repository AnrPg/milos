"use client";

import { useEffect } from "react";

/**
 * Marks the document once React has hydrated it (`<html data-hydrated>`), so
 * end-to-end tests wait for working buttons instead of tapping server HTML
 * whose handlers aren't attached yet. Rendered last in the root layout.
 */
export function HydrationMarker() {
  useEffect(() => {
    document.documentElement.dataset.hydrated = "true";
  }, []);
  return null;
}
