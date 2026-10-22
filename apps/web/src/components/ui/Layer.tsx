"use client";

import type { ReactNode } from "react";
import { createPortal } from "react-dom";

/**
 * Renders a full-screen surface (photo or media viewer, camera, full-page
 * picker) straight into <body>, so no transformed or z-indexed ancestor can
 * trap it below the nav. The surface itself sets its layer, for example
 * z-(--z-fullscreen).
 */
export function Layer({ children }: { children: ReactNode }) {
  if (typeof document === "undefined") return null;
  return createPortal(children, document.body);
}
