"use client";

import { useMemo } from "react";

import { qrSvgPath } from "./qr";

/**
 * A QR drawn on the device as one SVG path, black on white whatever the
 * theme (a camera needs the contrast). `label` names it for screen readers.
 */
export function QrCode({ value, label, className, testId }: { value: string; label: string; className?: string; testId?: string }) {
  const { size, path } = useMemo(() => qrSvgPath(value), [value]);
  return (
    <svg
      role="img"
      aria-label={label}
      data-testid={testId}
      data-value={value}
      viewBox={`0 0 ${size} ${size}`}
      shapeRendering="crispEdges"
      className={className}
      style={{ background: "var(--paper)", borderRadius: "0.75rem" }}
    >
      <rect width={size} height={size} fill="var(--paper)" />
      <path d={path} fill="var(--on-paper)" />
    </svg>
  );
}
