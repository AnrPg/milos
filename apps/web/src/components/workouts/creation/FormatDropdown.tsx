"use client";

import { useCallback, useRef, useState } from "react";

import { AUTO_SCORE_MAP, FORMAT_GROUPS, FORMAT_LABELS, FORMAT_TOOLTIPS, type SectionFormat } from "@/types/workout";

type FormatDropdownProps = {
  value: SectionFormat;
  onChange: (format: SectionFormat) => void;
};

export function FormatDropdown({ value, onChange }: FormatDropdownProps) {
  const [open, setOpen] = useState(false);
  const [hoveredFormat, setHoveredFormat] = useState<SectionFormat | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  const close = useCallback(() => {
    setOpen(false);
    setHoveredFormat(null);
  }, []);

  function handleSelect(format: SectionFormat) {
    onChange(format);
    close();
  }

  const tooltip = hoveredFormat ? FORMAT_TOOLTIPS[hoveredFormat] : null;

  return (
    <div ref={containerRef} className="relative w-full">
      <button
        type="button"
        onClick={() => setOpen((current) => !current)}
        className="flex w-full items-center justify-between rounded-xl px-3 py-2 text-sm font-semibold transition-colors"
        style={{
          background: "var(--card)",
          border: `1px solid ${open ? "var(--accent)" : "var(--dim)"}`,
          color: "var(--text)",
        }}
      >
        <span>{FORMAT_LABELS[value]}</span>
        <span style={{ color: "var(--muted)" }}>{open ? "^" : "v"}</span>
      </button>

      {open ? (
        <>
          <div className="fixed inset-0 z-40" onClick={close} />

          <div className="absolute left-0 top-full z-50 mt-1 flex">
            <div
              className="max-h-[360px] min-w-[220px] overflow-y-auto rounded-xl py-2"
              style={{
                background: "var(--card)",
                border: "1px solid var(--dim)",
                boxShadow: "0 8px 32px rgba(0,0,0,0.5)",
              }}
            >
              {FORMAT_GROUPS.map((group) => (
                <div key={group.label}>
                  <div
                    className="px-3 py-1 text-xs font-bold uppercase tracking-widest"
                    style={{ color: "var(--dim)" }}
                  >
                    {group.label}
                  </div>
                  {group.formats.map((format) => (
                    <button
                      key={format}
                      type="button"
                      onClick={() => handleSelect(format)}
                      onMouseEnter={() => setHoveredFormat(format)}
                      onMouseLeave={() => setHoveredFormat(null)}
                      className="flex w-full items-center justify-between px-3 py-2 text-left text-sm transition-colors"
                      style={{
                        background:
                          format === value
                            ? "color-mix(in srgb, var(--accent) 14%, transparent)"
                            : hoveredFormat === format
                              ? "color-mix(in srgb, var(--card) 88%, white 12%)"
                              : "transparent",
                        color: format === value ? "var(--accent)" : "var(--text)",
                      }}
                    >
                      <span>{FORMAT_LABELS[format]}</span>
                      {AUTO_SCORE_MAP[format] ? (
                        <span className="ml-2 text-xs" style={{ color: "var(--muted)" }}>
                          {AUTO_SCORE_MAP[format]}
                        </span>
                      ) : null}
                    </button>
                  ))}
                </div>
              ))}
            </div>

            {tooltip ? (
              <div
                className="pointer-events-none ml-2 w-[240px] shrink-0 self-start rounded-xl p-4 text-xs"
                style={{
                  background: "var(--panel)",
                  border: "1px solid var(--dim)",
                  color: "var(--text)",
                  boxShadow: "0 8px 32px rgba(0,0,0,0.5)",
                }}
              >
                <div className="mb-2 font-bold">{FORMAT_LABELS[hoveredFormat!]}</div>
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
          </div>
        </>
      ) : null}
    </div>
  );
}
