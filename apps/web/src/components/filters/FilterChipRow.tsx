"use client";

import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { useTranslations } from "next-intl";

// The list-screen filter pattern (vision §7.2, plan §5a): one horizontally
// scrolling chip row whose first chip is «Φίλτρα (n)» with a ✕ that clears
// everything. On/off chips toggle; chips with options open a small menu
// right under the chip.

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

const chipBase =
  "flex h-9 shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full px-3.5 text-sm font-semibold";

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
}: {
  ariaLabel: string;
  activeCount: number;
  onOpenFilters: () => void;
  onClear: () => void;
  chips: FilterChip[];
}) {
  const t = useTranslations("Filters");
  const [open, setOpen] = useState<{ key: string; anchor: HTMLElement } | null>(null);
  const openKey = open?.key ?? null;
  const openChip = chips.find((chip) => chip.key === openKey && chip.kind === "menu") as
    | Extract<FilterChip, { kind: "menu" }>
    | undefined;

  return (
    <div role="toolbar" aria-label={ariaLabel} className="-mx-4 flex gap-2 overflow-x-auto px-4 pb-1 [scrollbar-width:none]">
      <span className={`${chipBase} pr-1.5`} style={chipStyle(activeCount > 0, true)}>
        <button type="button" onClick={onOpenFilters} className="flex h-full items-center">
          {t("filtersCount", { count: activeCount })}
        </button>
        {activeCount > 0 ? (
          <button
            type="button"
            onClick={onClear}
            aria-label={t("clearAll")}
            className="grid h-6 w-6 place-items-center rounded-full"
            style={{ color: "var(--primary-strong)" }}
          >
            <span aria-hidden="true">✕</span>
          </button>
        ) : null}
      </span>

      {chips.map((chip) =>
        chip.kind === "toggle" ? (
          <button
            key={chip.key}
            type="button"
            aria-pressed={chip.active}
            onClick={chip.onToggle}
            className={chipBase}
            style={chipStyle(chip.active)}
          >
            {chip.label}
          </button>
        ) : (
          <button
            key={chip.key}
            type="button"
            aria-haspopup="menu"
            aria-expanded={openKey === chip.key}
            onClick={(event) => {
              const anchor = event.currentTarget;
              setOpen((current) => (current?.key === chip.key ? null : { key: chip.key, anchor }));
            }}
            className={chipBase}
            style={chipStyle(chip.selected.length > 0)}
          >
            {menuChipLabel(chip)}
            <span aria-hidden="true" className="text-xs" style={{ color: "var(--dim)" }}>
              ▾
            </span>
          </button>
        ),
      )}

      {openChip ? (
        <ChipMenu
          anchor={open?.anchor ?? null}
          chip={openChip}
          onClose={() => setOpen(null)}
        />
      ) : null}
    </div>
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
  const [position, setPosition] = useState<{ top: number; left: number } | null>(null);

  // The row scrolls sideways, so the menu is placed against the viewport.
  useLayoutEffect(() => {
    if (!anchor) return;
    const place = () => {
      const rect = anchor.getBoundingClientRect();
      const width = menu.current?.offsetWidth ?? 220;
      setPosition({ top: rect.bottom + 6, left: Math.max(8, Math.min(rect.left, window.innerWidth - width - 8)) });
    };
    place();
    window.addEventListener("resize", place);
    window.addEventListener("scroll", place, true);
    return () => {
      window.removeEventListener("resize", place);
      window.removeEventListener("scroll", place, true);
    };
  }, [anchor]);

  useEffect(() => {
    const onPointer = (event: PointerEvent) => {
      const target = event.target as Node;
      if (!menu.current?.contains(target) && !anchor?.contains(target)) onClose();
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        onClose();
        anchor?.focus();
      }
    };
    document.addEventListener("pointerdown", onPointer);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("pointerdown", onPointer);
      document.removeEventListener("keydown", onKey);
    };
  }, [anchor, onClose]);

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
    <div
      ref={menu}
      role="menu"
      aria-label={chip.label}
      className="fixed z-[60] grid max-h-80 min-w-48 max-w-72 gap-0.5 overflow-y-auto rounded-2xl p-1.5 shadow-2xl"
      style={{
        top: position?.top ?? -9999,
        left: position?.left ?? -9999,
        background: "var(--panel-raised)",
        border: "1px solid var(--border)",
      }}
    >
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
