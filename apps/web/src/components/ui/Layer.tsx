"use client";

import type { ReactNode } from "react";
import { createPortal } from "react-dom";

import { useHideBottomNav } from "@/components/nav/bottom-nav-visibility";

/**
 * Renders a full-screen surface (photo or media viewer, camera, full-page
 * picker) straight into <body>, so no transformed or z-indexed ancestor can
 * trap it below the nav. The surface itself sets its layer, for example
 * z-(--z-fullscreen). While it is open the member app's bottom bar steps
 * aside; pass hidesBottomNav={false} for a small floating layer (a dropdown).
 */
export function Layer({ children, hidesBottomNav = true }: { children: ReactNode; hidesBottomNav?: boolean }) {
  useHideBottomNav(hidesBottomNav);
  if (typeof document === "undefined") return null;
  return createPortal(children, document.body);
}
