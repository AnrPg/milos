"use client";

import { useState } from "react";

import { FORMAT_LABELS, FORMAT_TOOLTIPS, type SectionFormat } from "@/types/workout";

type Props = {
  format: SectionFormat;
  children: React.ReactNode;
};

export function FormatTooltip({ format, children }: Props) {
  const [state, setState] = useState({ visible: false, x: 0, y: 0 });
  const tooltip = FORMAT_TOOLTIPS[format];

  function handleMouseMove(event: React.MouseEvent) {
    setState((prev) => ({ ...prev, x: event.clientX, y: event.clientY }));
  }

  const tooltipLeft = typeof window !== "undefined"
    ? Math.min(state.x + 14, window.innerWidth - 264)
    : state.x + 14;
  const tooltipTop = typeof window !== "undefined"
    ? Math.min(state.y + 14, window.innerHeight - 200)
    : state.y + 14;

  return (
    <span
      className="inline cursor-default"
      onMouseEnter={(e) => setState({ visible: true, x: e.clientX, y: e.clientY })}
      onMouseLeave={() => setState((prev) => ({ ...prev, visible: false }))}
      onMouseMove={handleMouseMove}
    >
      {children}
      {state.visible ? (
        <div
          className="pointer-events-none fixed z-50 w-[240px] rounded-xl p-4 text-xs"
          style={{
            top: tooltipTop,
            left: tooltipLeft,
            background: "var(--panel)",
            border: "1px solid var(--dim)",
            color: "var(--text)",
            boxShadow: "0 8px 32px rgba(0,0,0,0.5)",
          }}
        >
          <div className="mb-2 font-bold">{FORMAT_LABELS[format]}</div>
          <div className="mb-1">
            <span style={{ color: "var(--muted)" }}>Best for </span>
            {tooltip.bestFor}
          </div>
          <div className="mb-1">
            <span style={{ color: "var(--muted)" }}>Trains </span>
            {tooltip.trains}
          </div>
          <div className="mb-1">
            <span style={{ color: "var(--muted)" }}>How </span>
            {tooltip.how}
          </div>
          {tooltip.score ? (
            <div>
              <span style={{ color: "var(--muted)" }}>Score </span>
              {tooltip.score}
            </div>
          ) : null}
        </div>
      ) : null}
    </span>
  );
}
