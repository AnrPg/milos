"use client";

import { useEffect, useRef, useState } from "react";
import { useTranslations } from "next-intl";

import type { AnatomyHighlights, AnatomyPickLevel, AnatomyView } from "@/lib/anatomy/figure";
import type { MuscleNodeId } from "@/lib/anatomy/taxonomy";
import type { FigureController } from "@/lib/anatomy/renderer/figure-controller";

import { AnatomyThumb } from "./AnatomyThumb";
import { useAnatomyLabel, useAnatomyPalette, usePrefersReducedMotion } from "./use-anatomy-environment";

export type AnatomyFigureSize = "thumb" | "card" | "full";

export type AnatomyFigureProps = {
  /** Muscle node id (region, group or head) -> role colour. Meshes outside it render neutral. */
  highlights: AnatomyHighlights;
  /** `both` draws the front and back figures side by side. Default `front`. */
  view?: AnatomyView;
  /** Drag (pointer or touch) turns the body about its vertical axis; wheel/pinch zooms a little. */
  interactive?: boolean;
  /** Tap picks a group; a second tap in the same group picks the head under the pointer. */
  onPick?: (nodeId: MuscleNodeId, level: AnatomyPickLevel) => void;
  /** Animates the camera to frame this node (bounds from the atlas index). */
  focus?: MuscleNodeId | null;
  /** thumb ~64px tall, card ~240px tall, full: the container's width. Default `card`. */
  size?: AnatomyFigureSize;
  className?: string;
};

const HEIGHT_CLASS: Record<Exclude<AnatomyFigureSize, "thumb">, string> = {
  card: "h-60",
  full: "h-[min(70vh,40rem)] min-h-80",
};

/**
 * The 3D anatomy figure (ADR-164). three.js and the atlas load only when this
 * mounts in the browser (dynamic import inside an effect), never with the
 * main bundle or on the server. A non-interactive thumb renders as a cached
 * image through the shared thumbnail renderer, so it costs no WebGL context.
 */
export function AnatomyFigure({
  highlights,
  view = "front",
  interactive = false,
  onPick,
  focus = null,
  size = "card",
  className = "",
}: AnatomyFigureProps) {
  if (size === "thumb" && !interactive && !onPick && !focus) {
    return <AnatomyThumb highlights={highlights} view={view} className={className} />;
  }
  return (
    <LiveFigure
      highlights={highlights}
      view={view}
      interactive={interactive}
      onPick={onPick}
      focus={focus}
      size={size}
      className={className}
    />
  );
}

function LiveFigure({
  highlights,
  view,
  interactive,
  onPick,
  focus,
  size,
  className,
}: Required<Omit<AnatomyFigureProps, "onPick" | "focus">> & Pick<AnatomyFigureProps, "onPick" | "focus">) {
  const t = useTranslations("Anatomy");
  const label = useAnatomyLabel(highlights);
  const palette = useAnatomyPalette();
  const reducedMotion = usePrefersReducedMotion();
  const containerRef = useRef<HTMLDivElement>(null);
  const controllerRef = useRef<FigureController | null>(null);
  const onPickRef = useRef(onPick);
  const [status, setStatus] = useState<"loading" | "ready" | "error">("loading");
  const pickable = onPick != null;

  // Latest values for the mount effect, which must not re-run on every change.
  const initial = useRef({ highlights, view, interactive, focus: focus ?? null, palette, reducedMotion, pickable });

  useEffect(() => {
    onPickRef.current = onPick;
    initial.current = { highlights, view, interactive, focus: focus ?? null, palette, reducedMotion, pickable };
  });

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    let cancelled = false;
    let controller: FigureController | null = null;
    import("@/lib/anatomy/renderer/figure-controller")
      .then(({ createFigure }) => {
        const options = initial.current;
        return createFigure(container, {
          ...options,
          onPick: options.pickable ? (pick) => onPickRef.current?.(pick.nodeId, pick.level) : null,
        });
      })
      .then((created) => {
        if (cancelled) {
          created.dispose();
          return;
        }
        controller = created;
        controllerRef.current = created;
        setStatus("ready");
      })
      .catch(() => {
        if (!cancelled) setStatus("error");
      });
    return () => {
      cancelled = true;
      controller?.dispose();
      controllerRef.current = null;
    };
  }, []);

  useEffect(() => {
    controllerRef.current?.update({
      highlights,
      view,
      interactive,
      focus: focus ?? null,
      palette,
      reducedMotion,
      onPick: pickable ? (pick) => onPickRef.current?.(pick.nodeId, pick.level) : null,
    });
  }, [highlights, view, interactive, focus, palette, reducedMotion, pickable, status]);

  const sizeClass =
    size === "thumb"
      ? `h-16 ${view === "both" ? "aspect-square" : "aspect-[1/2]"}`
      : `${HEIGHT_CLASS[size]} ${size === "card" ? (view === "both" ? "aspect-square" : "aspect-[1/2]") : "w-full"}`;

  return (
    <div
      ref={containerRef}
      role="img"
      aria-label={label}
      aria-roledescription={interactive ? t("figure.interactiveRole") : undefined}
      aria-busy={status === "loading"}
      title={interactive ? t("figure.interactiveHint") : undefined}
      tabIndex={interactive ? 0 : undefined}
      data-anatomy-status={status}
      className={`relative overflow-hidden rounded-2xl outline-none focus-visible:ring-2 focus-visible:ring-[var(--primary)] ${sizeClass} ${className}`}
    >
      {status !== "ready" ? (
        <div className="absolute inset-0 flex items-center justify-center p-2 text-center text-xs text-[var(--muted)]">
          {status === "loading" ? (
            <span aria-hidden="true" className="h-3/4 w-1/3 rounded-full bg-[var(--panel-raised)] motion-safe:animate-pulse" />
          ) : (
            <span>{t("figure.unavailable")}</span>
          )}
        </div>
      ) : null}
    </div>
  );
}
