"use client";

import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { useTranslations } from "next-intl";

import { Popover } from "@/components/ui/Popover";
import { balancedLineBreak } from "@/lib/segment-layout";

// The list-screen filter pattern (vision §7.2, plan §5a): a chip row whose
// first chip is «Φίλτρα (n)» with a ✕ that clears everything. On/off chips
// toggle; chips with options open a small menu right under the chip. A `fit`
// row never scrolls sideways: it breaks into two balanced lines instead.

export type ChipOption = { value: string; label: string };

export type FilterChip =
  | { key: string; kind: "toggle"; label: string; active: boolean; onToggle: () => void }
  | {
      key: string;
      kind: "menu";
      /** Shown when nothing is picked, e.g. «Είδος». */
      label: string;
      options: ChipOption[];
      selected: string[];
      multiple: boolean;
      onChange: (values: string[]) => void;
    };

const GAP_PX = 8;

const chipBase =
  "flex h-9 shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full px-3.5 text-sm font-semibold";

/** A chip sharing its line's width with the others (a `fit` row on two lines). */
const stretched = "min-w-0 flex-auto justify-center";

function chipStyle(active: boolean, strong = false) {
  if (active) {
    return {
      background: "color-mix(in srgb, var(--primary) 16%, var(--panel))",
      border: "1px solid var(--primary)",
      color: "var(--text)",
    };
  }
  return {
    background: strong ? "var(--panel-raised)" : "var(--panel)",
    border: "1px solid var(--border)",
    color: strong ? "var(--text)" : "var(--text-soft)",
  };
}

/** «Είδος», «WOD», or «WOD +1» for a menu chip. */
export function menuChipLabel(chip: Extract<FilterChip, { kind: "menu" }>) {
  const picked = chip.options.filter((option) => chip.selected.includes(option.value));
  if (picked.length === 0) return chip.label;
  return picked.length === 1 ? picked[0].label : `${picked[0].label} +${picked.length - 1}`;
}

export function FilterChipRow({
  ariaLabel,
  activeCount,
  onOpenFilters,
  onClear,
  chips,
  leading,
  fit = false,
}: {
  ariaLabel: string;
  activeCount: number;
  onOpenFilters: () => void;
  onClear: () => void;
  chips: FilterChip[];
  /** Shown right after «Φίλτρα (n)», e.g. saved filters. Not measured, so not for `fit` rows. */
  leading?: ReactNode;
  /**
   * Never scroll sideways (Γύρω μου): one line when every chip fits at its
   * natural width, otherwise two balanced lines whose chips share the width.
   */
  fit?: boolean;
}) {
  const t = useTranslations("Filters");
  const container = useRef<HTMLDivElement>(null);
  const ruler = useRef<HTMLDivElement>(null);
  const [lineBreak, setLineBreak] = useState<number | null>(null);

  const measure = useCallback(() => {
    if (!fit || !container.current || !ruler.current) return;
    const widths = (Array.from(ruler.current.children) as HTMLElement[]).map((chip) => chip.offsetWidth);
    const next = balancedLineBreak(widths, container.current.clientWidth, GAP_PX);
    setLineBreak((current) => (current === next ? current : next));
  }, [fit]);

  // Labels change with the filter («Πότε» → «Σαββατοκύριακο»), so remeasure
  // every render (a handful of offsetWidth reads) and on every resize.
  useLayoutEffect(() => {
    measure();
  });

  useLayoutEffect(() => {
    const box = container.current;
    if (!fit || !box || typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(() => measure());
    observer.observe(box);
    void document.fonts?.ready.then(() => measure());
    return () => observer.disconnect();
  }, [fit, measure]);

  const stretch = fit && lineBreak !== null;
  const filtersChip = (
    <span key="filters" className={`${chipBase} pr-1.5 ${stretch ? stretched : ""}`} style={chipStyle(activeCount > 0, true)}>
      <button type="button" onClick={onOpenFilters} className="flex h-full min-w-0 items-center">
        <span className="truncate">{t("filtersCount", { count: activeCount })}</span>
      </button>
      {activeCount > 0 ? (
        <button
          type="button"
          onClick={onClear}
          aria-label={t("clearAll")}
          className="grid h-6 w-6 shrink-0 place-items-center rounded-full"
          style={{ color: "var(--primary-strong)" }}
        >
          <span aria-hidden="true">✕</span>
        </button>
      ) : null}
    </span>
  );
  const chipItems = chips.map((chip) =>
    chip.kind === "toggle" ? (
      <button
        key={chip.key}
        type="button"
        aria-pressed={chip.active}
        onClick={chip.onToggle}
        className={`${chipBase} ${stretch ? stretched : ""}`}
        style={chipStyle(chip.active)}
      >
        <span className="truncate">{chip.label}</span>
      </button>
    ) : (
      <FilterMenuChip key={chip.key} chip={chip} className={stretch ? stretched : ""} />
    ),
  );

  if (!fit) {
    return (
      <div role="toolbar" aria-label={ariaLabel} className="-mx-4 flex gap-2 overflow-x-auto px-4 pb-1 [scrollbar-width:none]">
        {filtersChip}
        {leading}
        {chipItems}
      </div>
    );
  }

  const items = [filtersChip, ...chipItems];
  const lines = lineBreak === null ? [items] : [items.slice(0, lineBreak), items.slice(lineBreak)];
  return (
    <div ref={container} className="relative min-w-0">
      {/* Off-screen copy at natural widths: what the line break is chosen from. */}
      <div aria-hidden="true" className="pointer-events-none absolute inset-x-0 top-0 h-0 overflow-hidden" style={{ visibility: "hidden" }}>
        <div ref={ruler} className="flex w-max">
          <span className={`${chipBase} pr-1.5`}>
            {t("filtersCount", { count: activeCount })}
            {activeCount > 0 ? <span className="h-6 w-6" /> : null}
          </span>
          {chips.map((chip) => (
            <span key={chip.key} className={chipBase}>
              {chip.kind === "toggle" ? (
                chip.label
              ) : (
                <>
                  {menuChipLabel(chip)}
                  <span className="text-xs">▾</span>
                </>
              )}
            </span>
          ))}
        </div>
      </div>
      <div role="toolbar" aria-label={ariaLabel} data-chip-row="" className="flex flex-col overflow-hidden" style={{ gap: GAP_PX }}>
        {lines.map((line, index) => (
          <div key={index} className="flex min-w-0" style={{ gap: GAP_PX }}>
            {line}
          </div>
        ))}
      </div>
    </div>
  );
}

/** A chip with options: a tap opens a small menu right under it. */
export function FilterMenuChip({
  chip,
  active,
  className = "",
}: {
  chip: Extract<FilterChip, { kind: "menu" }>;
  /** Highlighted as a filter in use; by default when something is picked. */
  active?: boolean;
  className?: string;
}) {
  const [anchor, setAnchor] = useState<HTMLElement | null>(null);
  return (
    <>
      <button
        type="button"
        aria-haspopup="menu"
        aria-expanded={anchor !== null}
        onClick={(event) => {
          const target = event.currentTarget;
          setAnchor((current) => (current ? null : target));
        }}
        className={`${chipBase} ${className}`}
        style={chipStyle(active ?? chip.selected.length > 0)}
      >
        <span className="truncate">{menuChipLabel(chip)}</span>
        <span aria-hidden="true" className="text-xs" style={{ color: "var(--dim)" }}>
          ▾
        </span>
      </button>
      {anchor ? <ChipMenu anchor={anchor} chip={chip} onClose={() => setAnchor(null)} /> : null}
    </>
  );
}

function ChipMenu({
  anchor,
  chip,
  onClose,
}: {
  anchor: HTMLElement | null;
  chip: Extract<FilterChip, { kind: "menu" }>;
  onClose: () => void;
}) {
  const menu = useRef<HTMLDivElement>(null);
  // The row may scroll sideways, so the menu floats on the popover layer,
  // placed against the viewport next to its chip.
  const anchorRef = useMemo(() => ({ current: anchor }), [anchor]);

  useEffect(() => {
    menu.current?.querySelector<HTMLElement>("[role^=menuitem]")?.focus();
  }, []);

  function choose(value: string) {
    if (chip.multiple) {
      chip.onChange(
        chip.selected.includes(value) ? chip.selected.filter((item) => item !== value) : [...chip.selected, value],
      );
    } else {
      chip.onChange(chip.selected.includes(value) ? [] : [value]);
      onClose();
    }
  }

  return (
    <Popover
      anchorRef={anchorRef}
      open
      onClose={onClose}
      role="menu"
      ariaLabel={chip.label}
      minWidth={192}
      className="max-w-72 rounded-2xl shadow-2xl"
      style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", maxHeight: "20rem" }}
    >
      <div ref={menu} className="grid gap-0.5 p-1.5">
      {chip.options.map((option) => {
        const checked = chip.selected.includes(option.value);
        return (
          <MenuItem
            key={option.value}
            role={chip.multiple ? "menuitemcheckbox" : "menuitemradio"}
            checked={checked}
            onSelect={() => choose(option.value)}
          >
            {option.label}
          </MenuItem>
        );
      })}
      </div>
    </Popover>
  );
}

function MenuItem({
  role,
  checked,
  onSelect,
  children,
}: {
  role: "menuitemcheckbox" | "menuitemradio";
  checked: boolean;
  onSelect: () => void;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      role={role}
      aria-checked={checked}
      onClick={onSelect}
      className="flex min-h-10 items-center justify-between gap-3 rounded-xl px-3 text-left text-sm font-semibold"
      style={{
        color: "var(--text)",
        background: checked ? "color-mix(in srgb, var(--primary) 14%, transparent)" : "transparent",
      }}
    >
      {children}
      <span aria-hidden="true" style={{ color: "var(--primary-strong)", visibility: checked ? "visible" : "hidden" }}>
        ✓
      </span>
    </button>
  );
}
