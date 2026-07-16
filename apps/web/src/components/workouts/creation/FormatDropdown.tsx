"use client";




import {useUiTranslations} from "@/i18n/ui";
import { useCallback, useRef, useState } from "react";

import { getFormatGroups, getFormatLabels, getFormatTooltips, type SectionFormat } from "@/types/workout";

type FormatDropdownProps = {
  value: SectionFormat;
  onChange: (format: SectionFormat) => void;
};

type DropdownRect = {
  top?: number;
  bottom?: number;
  left: number;
  width: number;
  maxHeight: number;
};

export function FormatDropdown({ value, onChange }: FormatDropdownProps) {
  const i18n = useUiTranslations();
  const formatGroups = getFormatGroups(i18n);
  const formatLabels = getFormatLabels(i18n);
  const formatTooltips = getFormatTooltips(i18n);
  const [open, setOpen] = useState(false);
  const [hoveredFormat, setHoveredFormat] = useState<SectionFormat | null>(null);
  const [dropdownRect, setDropdownRect] = useState<DropdownRect | null>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);

  const close = useCallback(() => {
    setOpen(false);
    setHoveredFormat(null);
  }, []);

  function openDropdown() {
    if (!triggerRef.current) return;
    const rect = triggerRef.current.getBoundingClientRect();
    const spaceBelow = window.innerHeight - rect.bottom;
    const spaceAbove = rect.top;
    const openBelow = spaceBelow >= 200 || spaceBelow >= spaceAbove;
    const maxHeight = Math.max(120, openBelow
      ? Math.min(360, spaceBelow - 8)
      : Math.min(360, spaceAbove - 8));

    setDropdownRect({
      left: rect.left,
      width: rect.width,
      maxHeight,
      ...(openBelow
        ? { top: rect.bottom + 4 }
        : { bottom: window.innerHeight - rect.top + 4 }),
    });
    setOpen(true);
  }

  function handleSelect(format: SectionFormat) {
    onChange(format);
    close();
  }

  const tooltip = hoveredFormat ? formatTooltips[hoveredFormat] : null;

  return (
    <div className="relative w-full">
      <button
        ref={triggerRef}
        type="button"
        onClick={() => (open ? close() : openDropdown())}
        className="flex w-full items-center justify-between rounded-xl px-3 py-2 text-sm font-semibold transition-colors"
        style={{
          background: "var(--card)",
          border: `1px solid ${open ? "var(--accent)" : "var(--dim)"}`,
          color: "var(--text)",
        }}
      >
        <span>{formatLabels[value]}</span>
        <span style={{ color: "var(--muted)" }}>{open ? "▴" : "▾"}</span>
      </button>

      {open && dropdownRect ? (
        <>
          {/* Click-away overlay — scrolling in section config works independently */}
          <div className="fixed inset-0 z-40" onClick={close} />

          {/* Dropdown panel — fixed to viewport, escapes all overflow containers */}
          <div
            className="fixed z-50 flex"
            style={{
              top: dropdownRect.top,
              bottom: dropdownRect.bottom,
              left: dropdownRect.left,
              width: dropdownRect.width,
              alignItems: dropdownRect.bottom !== undefined ? "flex-end" : "flex-start",
            }}
          >
            <div
              className="min-w-[220px] w-full overflow-y-auto rounded-xl py-2"
              style={{
                maxHeight: dropdownRect.maxHeight,
                background: "var(--card)",
                border: "1px solid var(--dim)",
                boxShadow: "0 8px 32px rgba(0,0,0,0.5)",
              }}
            >
              {formatGroups.map((group) => (
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
                      className="w-full px-3 py-2 text-start text-sm transition-colors"
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
                      {formatLabels[format]}
                    </button>
                  ))}
                </div>
              ))}
            </div>

            {/* Tooltip — rendered as sibling so it never clips */}
            {tooltip ? (
              <div
                className="pointer-events-none ms-2 w-[240px] shrink-0 self-start rounded-xl p-4 text-xs"
                style={{
                  background: "var(--panel)",
                  border: "1px solid var(--dim)",
                  color: "var(--text)",
                  boxShadow: "0 8px 32px rgba(0,0,0,0.5)",
                }}
              >
                <div className="mb-2 font-bold">{formatLabels[hoveredFormat!]}</div>
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
          </div>
        </>
      ) : null}
    </div>
  );
}
