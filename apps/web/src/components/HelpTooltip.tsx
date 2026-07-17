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
