"use client";

import {
  Children,
  Fragment,
  isValidElement,
  useEffect,
  useId,
  useRef,
  useState,
  type ButtonHTMLAttributes,
  type CSSProperties,
  type KeyboardEvent,
  type ReactElement,
  type ReactNode,
} from "react";

import { Popover } from "./Popover";

/**
 * The app's dropdown (ADR-182). It replaces the native <select>, whose popup
 * the browser draws itself: off-theme, and on phones often wider than the
 * screen. The list opens in a ui/Popover, so it stays on screen, scrolls
 * inside itself and takes every colour from the theme.
 *
 * Options are written like a native select's, as <option> and <optgroup>
 * children, so markup carries over unchanged. The trigger is a combobox
 * button; `name` adds a hidden input so forms read the value as before.
 */

export type SelectItem = {
  value: string;
  label: ReactNode;
  /** Plain text of the label: typeahead and the accessible name. */
  text: string;
  disabled: boolean;
  group?: string;
};

type OptionProps = { value?: string | number; disabled?: boolean; children?: ReactNode; label?: string };
type GroupProps = { label?: string; disabled?: boolean; children?: ReactNode };

export function nodeText(node: ReactNode): string {
  if (node === null || node === undefined || typeof node === "boolean") return "";
  if (typeof node === "string" || typeof node === "number" || typeof node === "bigint") return String(node);
  if (Array.isArray(node)) return node.map(nodeText).join("");
  if (isValidElement<{ children?: ReactNode }>(node)) return nodeText(node.props.children);
  return "";
}

/** Reads <option>/<optgroup> children (also inside fragments and arrays) into items. */
export function selectItems(children: ReactNode, group?: string, groupDisabled = false): SelectItem[] {
  return Children.toArray(children).flatMap((child): SelectItem[] => {
    if (!isValidElement(child)) return [];
    if (child.type === Fragment) {
      return selectItems((child as ReactElement<{ children?: ReactNode }>).props.children, group, groupDisabled);
    }
    if (child.type === "optgroup") {
      const props = (child as ReactElement<GroupProps>).props;
      return selectItems(props.children, props.label, groupDisabled || Boolean(props.disabled));
    }
    if (child.type === "option") {
      const props = (child as ReactElement<OptionProps>).props;
      const label = props.children ?? props.label ?? "";
      const text = nodeText(label);
      return [{
        value: props.value === undefined ? text : String(props.value),
        label,
        text,
        disabled: groupDisabled || Boolean(props.disabled),
        group,
      }];
    }
    return [];
  });
}

export type SelectProps = Omit<
  ButtonHTMLAttributes<HTMLButtonElement>,
  "value" | "defaultValue" | "onChange" | "children" | "type" | "name" | "role"
> & {
  value?: string | number;
  defaultValue?: string | number;
  onValueChange?: (value: string) => void;
  /** <option> and <optgroup> elements, as in a native select. */
  children?: ReactNode;
  /** Shown when no option has the current value. */
  placeholder?: ReactNode;
  name?: string;
  required?: boolean;
  /** Extra classes for the list. */
  listClassName?: string;
};

const TYPEAHEAD_RESET_MS = 600;

export function Select({
  value,
  defaultValue,
  onValueChange,
  children,
  placeholder,
  name,
  required,
  disabled,
  className = "",
  style,
  listClassName = "",
  id,
  onKeyDown,
  onClick,
  ...rest
}: SelectProps) {
  const items = selectItems(children);
  const [inner, setInner] = useState(() => (defaultValue === undefined ? items[0]?.value ?? "" : String(defaultValue)));
  const current = value === undefined ? inner : String(value);
  const selectedIndex = items.findIndex((item) => item.value === current);
  // Like a native select, an unknown value shows the first option unless a placeholder is given.
  const shown = selectedIndex >= 0 ? items[selectedIndex] : placeholder === undefined ? items[0] : undefined;

  const [open, setOpen] = useState(false);
  const [active, setActive] = useState(-1);
  const [triggerWidth, setTriggerWidth] = useState<number | undefined>(undefined);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const typeahead = useRef({ text: "", at: 0 });
  const autoId = useId();
  const triggerId = id ?? `select-${autoId}`;
  const listId = `${triggerId}-list`;
  const optionId = (index: number) => `${triggerId}-opt-${index}`;

  const enabledIndexes = items.flatMap((item, index) => (item.disabled ? [] : [index]));

  function openList(focus: "selected" | "first" | "last" = "selected") {
    if (disabled || items.length === 0) return;
    const start =
      focus === "first" ? enabledIndexes[0] : focus === "last" ? enabledIndexes.at(-1) : selectedIndex >= 0 && !items[selectedIndex].disabled ? selectedIndex : enabledIndexes[0];
    setActive(start ?? -1);
    setTriggerWidth(triggerRef.current?.offsetWidth);
    setOpen(true);
  }

  function close(restore = true) {
    setOpen(false);
    if (restore) triggerRef.current?.focus();
  }

  function choose(index: number) {
    const item = items[index];
    if (!item || item.disabled) return;
    if (value === undefined) setInner(item.value);
    if (item.value !== current) onValueChange?.(item.value);
    close();
  }

  // Focus the list once it is on screen and keep the active option in view.
  useEffect(() => {
    if (!open) return;
    const frame = requestAnimationFrame(() => listRef.current?.focus({ preventScroll: true }));
    return () => cancelAnimationFrame(frame);
  }, [open]);

  useEffect(() => {
    if (!open || active < 0) return;
    document.getElementById(optionId(active))?.scrollIntoView?.({ block: "nearest" });
    // optionId is derived from the stable trigger id.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, active]);

  function step(from: number, delta: number) {
    if (enabledIndexes.length === 0) return -1;
    const position = enabledIndexes.indexOf(from);
    if (position < 0) return delta > 0 ? enabledIndexes[0] : enabledIndexes.at(-1)!;
    return enabledIndexes[Math.min(enabledIndexes.length - 1, Math.max(0, position + delta))];
  }

  function matchTypeahead(key: string, from: number, now: number) {
    const state = typeahead.current;
    state.text = now - state.at > TYPEAHEAD_RESET_MS ? key : state.text + key;
    state.at = now;
    const query = state.text.toLocaleLowerCase();
    const order = [...enabledIndexes.filter((index) => index > from), ...enabledIndexes.filter((index) => index <= from)];
    // A repeated single letter cycles through the options starting with it.
    const single = query.length > 1 && [...query].every((letter) => letter === query[0]) ? query[0] : null;
    return order.find((index) => items[index].text.toLocaleLowerCase().startsWith(single ?? query)) ?? -1;
  }

  function onTriggerKeyDown(event: KeyboardEvent<HTMLButtonElement>) {
    onKeyDown?.(event);
    if (event.defaultPrevented || disabled) return;
    if (event.key === "ArrowDown" || event.key === "ArrowUp" || event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      openList(event.key === "ArrowUp" && selectedIndex < 0 ? "last" : "selected");
      return;
    }
    if (event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey) {
      // Typing on a closed dropdown picks the matching option, as a native select does.
      const match = matchTypeahead(event.key, selectedIndex, event.timeStamp);
      if (match >= 0) {
        event.preventDefault();
        const item = items[match];
        if (value === undefined) setInner(item.value);
        if (item.value !== current) onValueChange?.(item.value);
      }
    }
  }

  function onListKeyDown(event: KeyboardEvent<HTMLDivElement>) {
    const page = 8;
    let next: number | null = null;
    if (event.key === "ArrowDown") next = step(active, 1);
    else if (event.key === "ArrowUp") next = step(active, -1);
    else if (event.key === "Home") next = enabledIndexes[0] ?? -1;
    else if (event.key === "End") next = enabledIndexes.at(-1) ?? -1;
    else if (event.key === "PageDown") next = step(active, page);
    else if (event.key === "PageUp") next = step(active, -page);
    else if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      choose(active);
      return;
    } else if (event.key === "Tab") {
      close(false);
      return;
    } else if (event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey) {
      const match = matchTypeahead(event.key, active, event.timeStamp);
      if (match >= 0) next = match;
    }
    if (next === null) return;
    event.preventDefault();
    if (next >= 0) setActive(next);
  }

  const triggerStyle: CSSProperties = {
    background: "var(--control-bg)",
    border: "1px solid var(--control-border)",
    color: "var(--text)",
    ...style,
  };

  return (
    <>
      <button
        {...rest}
        ref={triggerRef}
        id={triggerId}
        type="button"
        role="combobox"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={open ? listId : undefined}
        disabled={disabled}
        data-value={current}
        onClick={(event) => {
          onClick?.(event);
          if (event.defaultPrevented) return;
          if (open) close();
          else openList();
        }}
        onKeyDown={onTriggerKeyDown}
        className={`inline-flex min-w-0 items-center justify-between gap-2 text-start disabled:cursor-not-allowed disabled:opacity-60 ${className}`}
        style={triggerStyle}
      >
        <span className="min-w-0 flex-1 truncate" style={shown ? undefined : { color: "var(--placeholder)" }}>
          {shown ? shown.label : placeholder}
        </span>
        <svg aria-hidden="true" viewBox="0 0 20 20" className="h-4 w-4 shrink-0" style={{ color: "var(--select-chevron, var(--muted))", transform: open ? "rotate(180deg)" : undefined, transition: "transform 120ms" }}>
          <path d="M5 7.5 10 12.5 15 7.5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>
      {name ? <input type="hidden" name={name} value={selectedIndex >= 0 ? current : ""} /> : null}
      {required ? (
        // Lets the browser's form validation block an empty required choice.
        <input
          aria-hidden="true"
          tabIndex={-1}
          required
          value={selectedIndex >= 0 ? current : ""}
          onChange={() => undefined}
          onInvalid={() => triggerRef.current?.focus()}
          style={{ position: "absolute", width: 1, height: 1, opacity: 0, pointerEvents: "none" }}
        />
      ) : null}
      <Popover
        anchorRef={triggerRef}
        open={open}
        onClose={() => setOpen(false)}
        minWidth={triggerWidth}
        className={`rounded-2xl p-1 outline-none ${listClassName}`}
        style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)", boxShadow: "var(--shadow-lg)", maxHeight: "min(22rem, 60dvh)" }}
      >
        <div
          ref={listRef}
          role="listbox"
          id={listId}
          tabIndex={-1}
          aria-labelledby={triggerId}
          aria-activedescendant={active >= 0 ? optionId(active) : undefined}
          onKeyDown={onListKeyDown}
          className="outline-none"
        >
          {items.map((item, index) => {
            const header = item.group !== undefined && item.group !== items[index - 1]?.group ? item.group : null;
            const selected = index === selectedIndex;
            const isActive = index === active;
            return (
              <Fragment key={`${item.group ?? ""}:${item.value}:${index}`}>
                {header !== null ? (
                  <div role="presentation" className="px-3 pb-1 pt-2.5 text-[11px] font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>
                    {header}
                  </div>
                ) : null}
                <div
                  id={optionId(index)}
                  role="option"
                  data-value={item.value}
                  aria-selected={selected}
                  aria-disabled={item.disabled || undefined}
                  onPointerMove={() => !item.disabled && active !== index && setActive(index)}
                  onClick={() => choose(index)}
                  className={`flex min-h-11 cursor-pointer select-none items-center gap-2 rounded-xl px-3 py-2 text-sm ${item.disabled ? "cursor-not-allowed opacity-45" : ""}`}
                  style={{
                    background: selected
                      ? "color-mix(in srgb, var(--primary) 14%, transparent)"
                      : isActive
                        ? "color-mix(in srgb, var(--text) 7%, transparent)"
                        : undefined,
                    color: "var(--text)",
                    fontWeight: selected ? 600 : undefined,
                    outline: isActive ? "2px solid color-mix(in srgb, var(--focus-ring) 55%, transparent)" : undefined,
                    outlineOffset: -2,
                  }}
                >
                  <span className="min-w-0 flex-1 break-words">{item.label}</span>
                  {selected ? (
                    <svg aria-hidden="true" viewBox="0 0 20 20" className="h-4 w-4 shrink-0" style={{ color: "var(--primary)" }}>
                      <path d="M4.5 10.5 8.5 14.5 15.5 6" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                  ) : null}
                </div>
              </Fragment>
            );
          })}
        </div>
      </Popover>
    </>
  );
}
