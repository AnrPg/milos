"use client";

import { useRef, useState, type PointerEvent as ReactPointerEvent } from "react";

import { labelPosition, normalizedPoint, rectangleFromDrag, svgPoints, type Point } from "@/components/spaces/floor-plan";

export type PlanArea = {
  id: string;
  label: string;
  points: number[][];
  /** How the area is drawn: the selected one, a done one, one still due. */
  tone?: "default" | "selected" | "done" | "due" | "busy";
};

const fills: Record<NonNullable<PlanArea["tone"]>, { fill: string; stroke: string }> = {
  default: { fill: "color-mix(in srgb, var(--primary) 18%, transparent)", stroke: "var(--primary)" },
  selected: { fill: "color-mix(in srgb, var(--primary) 38%, transparent)", stroke: "var(--primary)" },
  done: { fill: "color-mix(in srgb, var(--success) 30%, transparent)", stroke: "var(--success)" },
  due: { fill: "color-mix(in srgb, var(--warning) 26%, transparent)", stroke: "var(--warning)" },
  busy: { fill: "color-mix(in srgb, var(--primary) 30%, transparent)", stroke: "var(--primary)" },
};

/**
 * A floor plan image with the spaces drawn on it (ADR-202). Areas are
 * buttons: tapping one selects its space. While `drawing`, a drag draws a
 * rectangle and `onDraw` receives its four normalized points.
 */
export function FloorPlanCanvas({
  imageUrl,
  alt,
  areas,
  onAreaClick,
  drawing = false,
  onDraw,
  testId,
}: {
  imageUrl: string | null | undefined;
  alt: string;
  areas: PlanArea[];
  onAreaClick?: (id: string) => void;
  drawing?: boolean;
  onDraw?: (points: Point[]) => void;
  testId?: string;
}) {
  const boxRef = useRef<HTMLDivElement>(null);
  const [start, setStart] = useState<Point | null>(null);
  const [current, setCurrent] = useState<Point | null>(null);

  const point = (event: ReactPointerEvent) => {
    const box = boxRef.current?.getBoundingClientRect();
    return box ? normalizedPoint(event.clientX, event.clientY, box) : null;
  };

  const preview = start && current ? rectangleFromDrag(start, current) : null;

  return (
    <div
      ref={boxRef}
      className="relative w-full select-none overflow-hidden rounded-2xl"
      data-testid={testId}
      data-drawing={drawing ? "true" : "false"}
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", touchAction: drawing ? "none" : "auto", cursor: drawing ? "crosshair" : "default" }}
      onPointerDown={(event) => {
        if (!drawing) return;
        const at = point(event);
        if (!at) return;
        (event.target as Element).setPointerCapture?.(event.pointerId);
        setStart(at);
        setCurrent(at);
      }}
      onPointerMove={(event) => {
        if (drawing && start) setCurrent(point(event));
      }}
      onPointerUp={(event) => {
        if (!drawing || !start) return;
        const end = point(event) ?? current;
        const rectangle = end ? rectangleFromDrag(start, end) : null;
        setStart(null);
        setCurrent(null);
        if (rectangle) onDraw?.(rectangle);
      }}
    >
      {imageUrl ? (
        // A signed, short-lived URL from object storage: next/image would cache it.
        // eslint-disable-next-line @next/next/no-img-element
        <img src={imageUrl} alt={alt} className="block h-auto w-full" draggable={false} />
      ) : (
        <div className="aspect-[4/3] w-full" aria-label={alt} role="img" />
      )}
      <svg className="absolute inset-0 h-full w-full" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden={drawing ? "true" : undefined}>
        {areas.map((area) => {
          const tone = fills[area.tone ?? "default"];
          return (
            <polygon
              key={area.id}
              points={svgPoints(area.points)}
              fill={tone.fill}
              stroke={tone.stroke}
              strokeWidth={0.4}
              vectorEffect="non-scaling-stroke"
            />
          );
        })}
        {preview ? (
          <polygon points={svgPoints(preview)} fill="color-mix(in srgb, var(--primary) 24%, transparent)" stroke="var(--primary)" strokeDasharray="1 1" strokeWidth={0.4} />
        ) : null}
      </svg>
      {areas.map((area) => {
        const at = labelPosition(area.points);
        return (
          <button
            key={area.id}
            type="button"
            disabled={drawing || !onAreaClick}
            data-testid={`plan-area-${area.id}`}
            aria-pressed={area.tone === "selected" || area.tone === "done" ? true : undefined}
            className="absolute -translate-x-1/2 -translate-y-1/2 rounded-full px-2 py-1 text-xs font-semibold shadow-[var(--shadow-sm)] disabled:cursor-default"
            style={{ left: `${at.x}%`, top: `${at.y}%`, background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)", pointerEvents: drawing ? "none" : "auto" }}
            onClick={() => onAreaClick?.(area.id)}
          >
            {area.label}
          </button>
        );
      })}
    </div>
  );
}
