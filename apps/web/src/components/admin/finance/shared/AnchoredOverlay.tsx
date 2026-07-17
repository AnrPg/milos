"use client";

import { useLayoutEffect, useRef, useState, type CSSProperties, type ReactNode, type RefObject } from "react";
import { createPortal } from "react-dom";

import { floatingPosition } from "./floating-position";

export function AnchoredOverlay({
  anchorRef,
  children,
  className,
  style,
  minWidth = 200,
  width,
  overlayRef,
}: {
  anchorRef: RefObject<HTMLElement | null>;
  children: ReactNode;
  className?: string;
  style?: CSSProperties;
  minWidth?: number;
  width?: number;
  overlayRef?: RefObject<HTMLDivElement | null>;
}) {
  const internalRef = useRef<HTMLDivElement>(null);
  const targetRef = overlayRef ?? internalRef;
  const [position, setPosition] = useState<{ left: number; top: number } | null>(null);

  useLayoutEffect(() => {
    const update = () => {
      const anchor = anchorRef.current;
      const overlay = targetRef.current;
      if (!anchor || !overlay) return;

      const rect = anchor.getBoundingClientRect();
      const overlayRect = overlay.getBoundingClientRect();
      setPosition(
        floatingPosition(
          rect,
          {
            width: width ?? Math.max(minWidth, overlayRect.width),
            height: overlayRect.height,
          },
          { width: window.innerWidth, height: window.innerHeight },
        ),
      );
    };

    update();
    window.addEventListener("resize", update);
    window.addEventListener("scroll", update, true);
    return () => {
      window.removeEventListener("resize", update);
      window.removeEventListener("scroll", update, true);
    };
  }, [anchorRef, minWidth, targetRef, width]);

  if (typeof document === "undefined") return null;

  return createPortal(
    <div
      ref={targetRef}
      className={className}
      style={{
        ...style,
        position: "fixed",
        left: position?.left ?? -10_000,
        top: position?.top ?? -10_000,
        minWidth,
        width,
        zIndex: 100,
      }}
    >
      {children}
    </div>,
    document.body,
  );
}
