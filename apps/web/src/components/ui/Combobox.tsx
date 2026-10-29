"use client";

import { useId, useRef, useState, type CSSProperties, type InputHTMLAttributes, type KeyboardEvent, type ReactNode } from "react";

import { Popover } from "./Popover";

export type ComboboxOption = {
  id: string;
  label: string;
  /** A second line or trailing note (an alias, a format's fields). */
  hint?: ReactNode;
};

type Props = Omit<InputHTMLAttributes<HTMLInputElement>, "value" | "onChange" | "onSelect" | "role"> & {
  value: string;
  onValueChange: (text: string) => void;
  /** The suggestions for the current text, best first (the caller filters). */
  options: ComboboxOption[];
  onPick: (option: ComboboxOption) => void;
  /** Shown in the list when nothing matches; omit to close the list instead. */
  emptyText?: ReactNode;
  /** Open the list as soon as the field gets focus (a format picker), not only once the coach types. */
  openOnFocus?: boolean;
  listLabel: string;
  listMinWidth?: number;
  inputStyle?: CSSProperties;
};

/**
 * A text field with a list of suggestions (WAI-ARIA combobox with a listbox,
 * focus staying in the field and `aria-activedescendant` naming the active
 * option). Typing opens the list; ↓/↑ move in it while it is open, Enter or
 * Tab take the active suggestion, Esc closes it. With the list closed the
 * arrow keys are left to the screen (row-to-row moves in the WOD editor);
 * Alt+↓ opens it. The coach may always keep their own words.
 */
export function Combobox({
  value,
  onValueChange,
  options,
  onPick,
  emptyText,
  openOnFocus = false,
  listLabel,
  listMinWidth = 240,
  inputStyle,
  onKeyDown,
  onFocus,
  onBlur,
  className,
  ...inputProps
}: Props) {
  const listId = useId();
  const inputRef = useRef<HTMLInputElement>(null);
  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(0);
  const showList = open && (options.length > 0 || Boolean(emptyText));
  const activeIndex = Math.min(active, options.length - 1);
  const activeOption = showList && activeIndex >= 0 ? options[activeIndex] : undefined;

  function pick(option: ComboboxOption) {
    onPick(option);
    setOpen(false);
  }

  function handleKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === "ArrowDown" && event.altKey && !event.ctrlKey && !event.metaKey) {
      event.preventDefault();
      setOpen(true);
      setActive(0);
      return;
    }
    if (showList && !event.altKey && !event.ctrlKey && !event.metaKey) {
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault();
        const step = event.key === "ArrowDown" ? 1 : -1;
        setActive((current) => (Math.min(current, options.length - 1) + step + options.length) % Math.max(options.length, 1));
        return;
      }
      // Enter or Tab take the active suggestion. When the field already says
      // exactly that, the key keeps its usual meaning (Enter: next row).
      if ((event.key === "Enter" || event.key === "Tab") && !event.shiftKey && activeOption) {
        if (activeOption.label !== value) {
          pick(activeOption);
          if (event.key === "Enter") {
            event.preventDefault();
            return;
          }
        } else {
          setOpen(false);
        }
      }
      if (event.key === "Escape") {
        event.preventDefault();
        event.stopPropagation();
        setOpen(false);
        return;
      }
    }
    onKeyDown?.(event);
  }

  return (
    <>
      <input
        {...inputProps}
        ref={inputRef}
        type="text"
        role="combobox"
        autoComplete="off"
        spellCheck={false}
        aria-autocomplete="list"
        aria-expanded={showList}
        aria-controls={showList ? listId : undefined}
        aria-activedescendant={activeOption ? `${listId}-${activeOption.id}` : undefined}
        value={value}
        className={className}
        style={inputStyle}
        onChange={(event) => {
          onValueChange(event.target.value);
          setOpen(true);
          setActive(0);
        }}
        onKeyDown={handleKeyDown}
        onFocus={(event) => {
          if (openOnFocus) {
            setOpen(true);
            setActive(0);
          }
          onFocus?.(event);
        }}
        onBlur={(event) => {
          setOpen(false);
          onBlur?.(event);
        }}
      />
      <Popover
        anchorRef={inputRef}
        open={showList}
        onClose={() => setOpen(false)}
        minWidth={listMinWidth}
        role="listbox"
        id={listId}
        ariaLabel={listLabel}
        restoreFocus={false}
        className="rounded-2xl py-1 shadow-lg"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", maxHeight: 320 }}
      >
        {options.length === 0 ? (
          <div className="px-3 py-2 text-xs" style={{ color: "var(--muted)" }}>
            {emptyText}
          </div>
        ) : (
          options.map((option, index) => {
            const selected = index === activeIndex;
            return (
              <div
                key={option.id}
                id={`${listId}-${option.id}`}
                role="option"
                aria-selected={selected}
                // Keep focus in the field: a press must not blur it before the pick.
                onMouseDown={(event) => event.preventDefault()}
                onMouseEnter={() => setActive(index)}
                onClick={() => pick(option)}
                className="flex cursor-pointer items-baseline justify-between gap-3 px-3 py-2 text-sm"
                style={{
                  background: selected ? "color-mix(in srgb, var(--primary) 14%, transparent)" : "transparent",
                  color: "var(--text)",
                }}
              >
                <span className="font-semibold">{option.label}</span>
                {option.hint ? (
                  <span className="truncate text-xs" style={{ color: "var(--muted)" }}>
                    {option.hint}
                  </span>
                ) : null}
              </div>
            );
          })
        )}
      </Popover>
    </>
  );
}
