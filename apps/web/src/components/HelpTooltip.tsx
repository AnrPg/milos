"use client";

import { useId, useState } from "react";

export function HelpTooltip({ label, children }: { label: string; children: React.ReactNode }) {
  const id = useId();
  const [open, setOpen] = useState(false);

  return (
    <span className="group relative inline-flex align-middle">
      <button
        aria-describedby={open ? id : undefined}
        aria-expanded={open}
        aria-label={label}
        className="inline-flex h-5 w-5 items-center justify-center rounded-full text-[11px] font-bold"
        onBlur={() => setOpen(false)}
        onClick={() => setOpen((current) => !current)}
        onFocus={() => setOpen(true)}
        type="button"
        style={{
          background: "color-mix(in srgb, var(--primary) 12%, transparent)",
          border: "1px solid color-mix(in srgb, var(--primary) 28%, transparent)",
          color: "var(--primary)",
        }}
      >
        ?
      </button>
      <span
        id={id}
        role="tooltip"
        className={`${open ? "visible opacity-100" : "invisible opacity-0 group-hover:visible group-hover:opacity-100"} pointer-events-none absolute start-1/2 top-full z-[110] mt-2 w-64 -translate-x-1/2 rounded-xl px-3 py-2 text-start text-xs font-normal normal-case leading-5 tracking-normal shadow-xl transition-opacity`}
        style={{
          background: "var(--panel-raised)",
          border: "1px solid var(--border-strong)",
          color: "var(--text-soft)",
        }}
      >
        {children}
      </span>
    </span>
  );
}

const HINT_POSITION_CLASSES = { start: "start-0", center: "", end: "end-0" } as const;
// Physical centering works in both LTR and RTL layouts.
const CENTERED_HINT_STYLE = { left: "50%", transform: "translateX(-50%)" };

/**
 * Hover/focus infobox for compact controls (icon-only or emoji buttons).
 * Wrap the control; the hint appears below it on hover or keyboard focus.
 */
export function HoverHint({
  hint,
  align = "center",
  suppressed = false,
  children,
}: {
  hint: React.ReactNode;
  align?: "start" | "center" | "end";
  /** Keep the hint hidden, e.g. while the wrapped control's own menu is open. */
  suppressed?: boolean;
  children: React.ReactNode;
}) {
  const position = HINT_POSITION_CLASSES[align];

  return (
    <span className="group/hint relative inline-flex">
      {children}
      <span
        role="tooltip"
        className={`pointer-events-none invisible absolute top-full z-[110] mt-2 w-max max-w-56 rounded-lg px-2.5 py-1.5 text-start text-xs font-medium normal-case leading-5 tracking-normal opacity-0 shadow-xl transition-opacity delay-150 ${suppressed ? "" : "group-hover/hint:visible group-hover/hint:opacity-100 group-has-[:focus-visible]/hint:visible group-has-[:focus-visible]/hint:opacity-100"} ${position}`}
        style={{
          ...(align === "center" ? CENTERED_HINT_STYLE : null),
          background: "var(--panel-raised)",
          border: "1px solid var(--border-strong)",
          color: "var(--text-soft)",
        }}
      >
        {hint}
      </span>
    </span>
  );
}
