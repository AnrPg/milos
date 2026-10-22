"use client";

import { useLayoutEffect, useRef, useState, type KeyboardEvent, type ReactNode } from "react";

export type EditorTab<K extends string> = {
  key: K;
  label: string;
  /** Shown alone when the full labels do not fit (narrow screens, long languages). */
  icon: string;
  /** Small count or marker after the label, e.g. open problems. */
  badge?: ReactNode;
};

type Props<K extends string> = {
  label: string;
  tabs: EditorTab<K>[];
  /** The open tab; null keeps every panel closed so the text gets the room. */
  active: K | null;
  onSelect: (key: K | null) => void;
  /** Right-hand slot on the tab row (assistant switch, save status). */
  trailing?: ReactNode;
  children?: ReactNode;
};

/**
 * The WOD editors' settings as one row of tabs instead of stacked collapsible
 * ribbons. One panel is open at a time and pressing the open tab closes it.
 * When the full labels do not fit beside the trailing slot, the tabs show
 * their icons only (the label stays as the accessible name and tooltip).
 */
export function EditorTabs<K extends string>({ label, tabs, active, onSelect, trailing, children }: Props<K>) {
  const rowRef = useRef<HTMLDivElement>(null);
  const measureRef = useRef<HTMLDivElement>(null);
  const [compact, setCompact] = useState(false);

  useLayoutEffect(() => {
    const row = rowRef.current;
    const measure = measureRef.current;
    if (!row || !measure) return;
    const update = () => setCompact(measure.scrollWidth > row.clientWidth);
    update();
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(update);
    observer.observe(row);
    observer.observe(measure);
    return () => observer.disconnect();
  }, [tabs]);

  function onKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    const step = event.key === "ArrowRight" ? 1 : event.key === "ArrowLeft" ? -1 : 0;
    if (!step) return;
    const rtl = getComputedStyle(event.currentTarget).direction === "rtl";
    const current = Math.max(
      0,
      tabs.findIndex((tab) => tab.key === active),
    );
    const next = tabs[(current + (rtl ? -step : step) + tabs.length) % tabs.length]!;
    onSelect(next.key);
    event.currentTarget.querySelector<HTMLButtonElement>(`[data-tab="${next.key}"]`)?.focus();
    event.preventDefault();
  }

  return (
    <div className="min-w-0 border-b" style={{ borderColor: "var(--dim)" }}>
      <div className="relative flex min-w-0 items-center gap-2 px-3 py-2">
        <div ref={rowRef} className="min-w-0 flex-1 overflow-hidden">
          <div role="tablist" aria-label={label} className="flex gap-1" onKeyDown={onKeyDown}>
            {tabs.map((tab) => {
              const selected = tab.key === active;
              return (
                <button
                  key={tab.key}
                  data-tab={tab.key}
                  type="button"
                  role="tab"
                  id={`editor-tab-${tab.key}`}
                  aria-selected={selected}
                  aria-controls={selected ? `editor-panel-${tab.key}` : undefined}
                  aria-label={compact ? tab.label : undefined}
                  title={compact ? tab.label : undefined}
                  tabIndex={selected || (active === null && tab === tabs[0]) ? 0 : -1}
                  onClick={() => onSelect(selected ? null : tab.key)}
                  className="flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-lg px-2.5 py-1.5 text-xs font-black"
                  style={{
                    background: selected ? "var(--card)" : "transparent",
                    color: selected ? "var(--text)" : "var(--muted)",
                    boxShadow: selected ? "inset 0 -2px 0 var(--primary)" : undefined,
                  }}
                >
                  <span aria-hidden="true">{tab.icon}</span>
                  {compact ? null : <span>{tab.label}</span>}
                  {tab.badge}
                </button>
              );
            })}
          </div>
        </div>
        {/* Full labels, laid out off-screen, to know whether they fit. */}
        <div
          ref={measureRef}
          aria-hidden="true"
          className="pointer-events-none invisible absolute start-0 top-0 flex w-max gap-1"
        >
          {tabs.map((tab) => (
            <span key={tab.key} className="flex shrink-0 items-center gap-1.5 whitespace-nowrap px-2.5 py-1.5 text-xs font-black">
              <span>{tab.icon}</span>
              <span>{tab.label}</span>
              {tab.badge}
            </span>
          ))}
        </div>
        {trailing ? <div className="flex shrink-0 items-center gap-2">{trailing}</div> : null}
      </div>
      {active !== null && children ? (
        <div
          role="tabpanel"
          id={`editor-panel-${active}`}
          aria-labelledby={`editor-tab-${active}`}
          className="min-w-0 overflow-x-clip border-t"
          style={{ borderColor: "color-mix(in srgb, var(--dim) 70%, transparent)" }}
        >
          {children}
        </div>
      ) : null}
    </div>
  );
}
