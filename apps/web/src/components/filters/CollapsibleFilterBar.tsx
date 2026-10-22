"use client";

import { useId, useState, type ReactNode, type Ref } from "react";
import { useTranslations } from "next-intl";

// The list-screen search pattern for every console screen: only the search
// field and a filter button show; the filter form opens under them when the
// button is pressed. The button carries the number of filters in force, so a
// collapsed bar never hides that the list is filtered. The form opens in the
// page flow (no overlay), so it works the same on phones and desktops.

export type FilterBarSearch = {
  value: string;
  onChange: (value: string) => void;
  placeholder: string;
  ariaLabel: string;
  /** A keyboard hint shown at the end of the field on wide screens, e.g. «/». */
  shortcut?: string;
  maxLength?: number;
};

function SlidersIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 20 20" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
      <path d="M3 5.5h8M15 5.5h2M3 14.5h2M9 14.5h8" />
      <circle cx="13" cy="5.5" r="2" />
      <circle cx="7" cy="14.5" r="2" />
    </svg>
  );
}

export function CollapsibleFilterBar({
  ariaLabel,
  search,
  searchRef,
  activeCount,
  onClear,
  summary,
  trailing,
  defaultOpen = false,
  children,
}: {
  ariaLabel: string;
  /** Leave out on screens that only filter. */
  search?: FilterBarSearch;
  searchRef?: Ref<HTMLInputElement>;
  /** Filters in force inside the form (the search text is not counted). */
  activeCount: number;
  /** Shown inside the open form while any filter is in force. */
  onClear?: () => void;
  /** Always visible under the bar, e.g. «12 of 40 · Clear filters». */
  summary?: ReactNode;
  /** Extra controls after the filter button, e.g. a view switch. */
  trailing?: ReactNode;
  defaultOpen?: boolean;
  /** The filter form. */
  children: ReactNode;
}) {
  const t = useTranslations("Filters");
  const panelId = useId();
  const [open, setOpen] = useState(defaultOpen);

  const toggle = () => setOpen((current) => !current);

  return (
    <section
      role="search"
      aria-label={ariaLabel}
      className="space-y-3 rounded-[1.6rem] p-3 sm:p-4"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div className="flex items-center gap-2">
        {search ? (
          <div className="relative min-w-0 flex-1">
            <span aria-hidden="true" className="pointer-events-none absolute inset-y-0 start-3 flex items-center text-sm" style={{ color: "var(--dim)" }}>
              ⌕
            </span>
            <input
              ref={searchRef}
              type="search"
              aria-label={search.ariaLabel}
              placeholder={search.placeholder}
              value={search.value}
              maxLength={search.maxLength}
              onChange={(event) => search.onChange(event.target.value)}
              className={`min-h-11 w-full rounded-xl py-2.5 ps-9 text-sm outline-none ${search.shortcut ? "sm:pe-12" : ""} pe-3`}
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            />
            {search.shortcut ? (
              <kbd
                className="pointer-events-none absolute inset-y-0 end-3 my-auto hidden h-6 items-center rounded-md px-2 text-[11px] sm:flex"
                style={{ border: "1px solid var(--border)", color: "var(--dim)" }}
              >
                {search.shortcut}
              </kbd>
            ) : null}
          </div>
        ) : null}

        <button
          type="button"
          onClick={toggle}
          aria-expanded={open}
          aria-controls={panelId}
          aria-label={search ? t("filtersCount", { count: activeCount }) : undefined}
          className={`relative inline-flex min-h-11 shrink-0 items-center justify-center gap-1.5 rounded-xl px-3 text-sm font-semibold ${search ? "" : "flex-1 sm:flex-none"}`}
          style={
            open || activeCount > 0
              ? { background: "color-mix(in srgb, var(--primary) 14%, var(--panel))", border: "1px solid var(--primary)", color: "var(--text)" }
              : { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text-soft)" }
          }
        >
          <SlidersIcon />
          <span className={search ? "hidden sm:inline" : ""}>{t("filtersCount", { count: activeCount })}</span>
          {search && activeCount > 0 ? (
            <span
              aria-hidden="true"
              className="grid h-5 min-w-5 place-items-center rounded-full px-1 text-[11px] font-bold tabular-nums sm:hidden"
              style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}
            >
              {activeCount}
            </span>
          ) : null}
          <span aria-hidden="true" className="text-xs transition-transform" style={{ transform: open ? "rotate(180deg)" : undefined }}>
            ▾
          </span>
        </button>
        {trailing}
      </div>

      <div id={panelId} hidden={!open} className="space-y-3">
        {children}
        {onClear && activeCount > 0 ? (
          <div className="flex justify-end">
            <button type="button" onClick={onClear} className="text-sm font-semibold underline" style={{ color: "var(--primary)" }}>
              {t("clearAll")}
            </button>
          </div>
        ) : null}
      </div>

      {summary}
    </section>
  );
}
