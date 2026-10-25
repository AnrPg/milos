"use client";

import { useCallback, useLayoutEffect, useRef, useState, type CSSProperties, type KeyboardEvent, type ReactNode } from "react";

import { chooseSegmentLayout, fittingColumns, rowFits, type SegmentLayout } from "@/lib/segment-layout";
import { Select } from "@/components/ui/Select";
import type { GuideAnchor } from "@/lib/guides/anchors";

// One control for every set of mutually exclusive options shown as tabs or
// chips (user types, list tabs, sources, boxes). It never scrolls sideways:
// one row when every option fits, an exactly-filled grid (2×2, 2×3, 3×2…)
// when a row does not, and a dropdown when no grid is full. The choice is
// remeasured whenever the space or the labels change.

export type SegmentOption<T extends string> = {
  value: T;
  label: string;
  /** Shown as a badge on the chip and as «Label (n)» in the dropdown. */
  count?: number | string | null;
  disabled?: boolean;
};

type Variant = "chips" | "track";

const GAP_PX = 6;

function chipClass(variant: Variant, stretch: boolean) {
  return [
    "inline-flex min-h-10 min-w-0 items-center justify-center gap-2 whitespace-nowrap px-3.5 text-sm font-semibold transition-colors disabled:opacity-40",
    variant === "track" ? "rounded-full" : "rounded-xl",
    stretch ? "flex-1" : "",
  ].join(" ");
}

function chipStyle(variant: Variant, selected: boolean): CSSProperties {
  if (selected) return { background: "var(--text)", color: "var(--bg)", border: "1px solid var(--text)" };
  return variant === "track"
    ? { background: "transparent", color: "var(--muted)", border: "1px solid transparent" }
    : { background: "var(--panel)", color: "var(--text-soft)", border: "1px solid var(--border)" };
}

function Badge({ selected, children }: { selected: boolean; children: ReactNode }) {
  return (
    <span
      className="rounded-full px-1.5 text-[11px] font-bold tabular-nums"
      style={{ background: selected ? "color-mix(in srgb, var(--bg) 25%, transparent)" : "var(--panel-muted)" }}
    >
      {children}
    </span>
  );
}

function hasCount(count: SegmentOption<string>["count"]) {
  return count !== undefined && count !== null && count !== "";
}

export function SegmentPicker<T extends string>({
  options,
  value,
  onChange,
  ariaLabel,
  semantics = "tablist",
  idPrefix,
  panelId,
  variant = "chips",
  stretch = false,
  className = "",
  guide,
}: {
  options: SegmentOption<T>[];
  value: T;
  onChange: (value: T) => void;
  ariaLabel: string;
  /** `tablist` when the options switch a panel, `radiogroup` when they pick a value. */
  semantics?: "tablist" | "radiogroup";
  /** Gives each tab the id `${idPrefix}-tab-${value}` so a panel can point back at it. */
  idPrefix?: string;
  /** The id of the panel the tabs control (`aria-controls`). */
  panelId?: string;
  /** `track`: page-level tabs on a shared track. `chips`: separate chips. */
  variant?: Variant;
  /** Stretch the chips of a single row over the full width. */
  stretch?: boolean;
  className?: string;
  /** A walkthrough anchor (ADR-193); each chip also carries `data-segment`. */
  guide?: GuideAnchor;
}) {
  const container = useRef<HTMLDivElement>(null);
  const measurer = useRef<HTMLDivElement>(null);
  const [layout, setLayout] = useState<SegmentLayout>({ kind: "row" });

  const measure = useCallback(() => {
    const box = container.current;
    const ruler = measurer.current;
    if (!box || !ruler) return;
    // The track's padding and border take a little of the width.
    const width = box.clientWidth - (variant === "track" ? 6 : 0);
    if (width <= 0) return;
    const chips = Array.from(ruler.children) as HTMLElement[];
    const widths = chips.map((chip) => chip.offsetWidth);
    const widest = Math.max(0, ...widths);
    const next = chooseSegmentLayout({
      count: chips.length,
      rowFits: rowFits(widths, width, GAP_PX, stretch),
      columns: fittingColumns(width, widest, GAP_PX),
    });
    setLayout((current) =>
      current.kind === next.kind && (next.kind !== "grid" || (current.kind === "grid" && current.columns === next.columns))
        ? current
        : next,
    );
  }, [variant, stretch]);

  // Labels or counts changing can change the widths, so remeasure every render
  // (cheap: a handful of offsetWidth reads) and on every resize.
  useLayoutEffect(() => {
    measure();
  });

  useLayoutEffect(() => {
    const box = container.current;
    if (!box || typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(() => measure());
    observer.observe(box);
    void document.fonts?.ready.then(() => measure());
    return () => observer.disconnect();
  }, [measure]);

  const enabled = options.filter((option) => !option.disabled);
  const tabRefs = useRef(new Map<T, HTMLButtonElement>());

  function onKeyDown(event: KeyboardEvent<HTMLButtonElement>) {
    if (enabled.length === 0) return;
    const index = enabled.findIndex((option) => option.value === value);
    const rtl = getComputedStyle(event.currentTarget).direction === "rtl";
    const forward = rtl ? "ArrowLeft" : "ArrowRight";
    const backward = rtl ? "ArrowRight" : "ArrowLeft";
    let nextIndex: number;
    if (event.key === "Home") nextIndex = 0;
    else if (event.key === "End") nextIndex = enabled.length - 1;
    else if (event.key === "ArrowDown" || event.key === forward) nextIndex = (index + 1) % enabled.length;
    else if (event.key === "ArrowUp" || event.key === backward) nextIndex = (index - 1 + enabled.length) % enabled.length;
    else return;
    event.preventDefault();
    const next = enabled[nextIndex];
    onChange(next.value);
    tabRefs.current.get(next.value)?.focus();
  }

  const itemRole = semantics === "tablist" ? "tab" : "radio";
  const trackStyle: CSSProperties | undefined =
    variant === "track" ? { background: "var(--panel-muted)", border: "1px solid var(--border)", padding: 2, borderRadius: "1.25rem" } : undefined;

  return (
    <div ref={container} className={`relative min-w-0 ${className}`} data-guide={guide}>
      {/* Off-screen copy at natural widths: what the layout is chosen from. */}
      <div aria-hidden="true" className="pointer-events-none absolute inset-x-0 top-0 h-0 overflow-hidden" style={{ visibility: "hidden" }}>
        <div ref={measurer} className="flex w-max">
          {options.map((option) => (
            <span key={option.value} className={chipClass(variant, false)} style={chipStyle(variant, true)}>
              {option.label}
              {hasCount(option.count) ? <Badge selected>{option.count}</Badge> : null}
            </span>
          ))}
        </div>
      </div>

      {layout.kind === "select" ? (
        <Select
          aria-label={ariaLabel}
          value={value}
          onValueChange={(value) => onChange(value as T)}
          aria-controls={panelId}
          className="min-h-10 w-full rounded-xl px-3 text-sm font-semibold"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {options.map((option) => (
            <option key={option.value} value={option.value} disabled={option.disabled}>
              {hasCount(option.count) ? `${option.label} (${option.count})` : option.label}
            </option>
          ))}
        </Select>
      ) : (
        <div
          role={semantics}
          aria-label={ariaLabel}
          className={layout.kind === "grid" ? "grid" : stretch ? "flex" : "flex w-fit max-w-full"}
          style={{
            gap: variant === "track" ? 2 : GAP_PX,
            ...(layout.kind === "grid" ? { gridTemplateColumns: `repeat(${layout.columns}, minmax(0, 1fr))` } : null),
            ...trackStyle,
          }}
        >
          {options.map((option) => {
            const selected = option.value === value;
            return (
              <button
                key={option.value}
                ref={(node) => {
                  if (node) tabRefs.current.set(option.value, node);
                  else tabRefs.current.delete(option.value);
                }}
                type="button"
                role={itemRole}
                id={idPrefix ? `${idPrefix}-tab-${option.value}` : undefined}
                data-segment={option.value}
                aria-selected={semantics === "tablist" ? selected : undefined}
                aria-checked={semantics === "radiogroup" ? selected : undefined}
                aria-controls={semantics === "tablist" ? panelId : undefined}
                tabIndex={selected ? 0 : -1}
                disabled={option.disabled}
                onClick={() => onChange(option.value)}
                onKeyDown={onKeyDown}
                className={chipClass(variant, stretch || layout.kind === "grid")}
                style={chipStyle(variant, selected)}
              >
                <span className="truncate">{option.label}</span>
                {hasCount(option.count) ? <Badge selected={selected}>{option.count}</Badge> : null}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}
