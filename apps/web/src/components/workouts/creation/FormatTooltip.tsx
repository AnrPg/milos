"use client";



import {useUiTranslations} from "@/i18n/ui";
import { useState } from "react";

import { getFormatLabels, getFormatTooltips, type SectionFormat } from "@/types/workout";

type Props = {
  format: SectionFormat;
  children: React.ReactNode;
};

export function FormatTooltip({ format, children }: Props) {
  const i18n = useUiTranslations();
  const formatLabels = getFormatLabels(i18n);
  const formatTooltips = getFormatTooltips(i18n);
  const [state, setState] = useState({ visible: false, x: 0, y: 0 });
  const tooltip = formatTooltips[format];

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
          <div className="mb-2 font-bold">{formatLabels[format]}</div>
          <div className="mb-1">
            <span style={{ color: "var(--muted)" }}>{i18n("bestFor6d7ae87")} </span>
            {tooltip.bestFor}
          </div>
          <div className="mb-1">
            <span style={{ color: "var(--muted)" }}>{i18n("trainsd629bf5")} </span>
            {tooltip.trains}
          </div>
          <div className="mb-1">
            <span style={{ color: "var(--muted)" }}>{i18n("how0c81abc")} </span>
            {tooltip.how}
          </div>
          {tooltip.score ? (
            <div>
              <span style={{ color: "var(--muted)" }}>{i18n("score489f487")} </span>
              {tooltip.score}
            </div>
          ) : null}
        </div>
      ) : null}
    </span>
  );
}
