"use client";

import { useRef, type KeyboardEvent, type ReactNode } from "react";

/** The input look every wizard field shares (theme variables only). */
export const fieldClass = "min-h-11 w-full rounded-2xl px-3 text-sm font-normal";

export type SegmentOption<T extends string> = { value: T; label: ReactNode; hint?: ReactNode; disabled?: boolean };

/**
 * A single choice laid out on the full grid (never a scrolling row): two
 * columns for two options, a column of rows on phones and three across
 * from `sm` for three, two by two (three from `sm`) for more. A real
 * radiogroup: one tab stop, arrows move and choose, Home and End jump.
 */
export function SegmentGrid<T extends string>({
  label,
  labelledBy,
  value,
  onChange,
  options,
  stack = false,
}: {
  /** The group's accessible name, unless `labelledBy` points at a visible one. */
  label?: string;
  labelledBy?: string;
  value: T | null;
  onChange: (value: T) => void;
  options: SegmentOption<T>[];
  /** One option per row at every width (long labels such as host names). */
  stack?: boolean;
}) {
  const refs = useRef<(HTMLButtonElement | null)[]>([]);
  const enabled = options.map((option, index) => (option.disabled ? -1 : index)).filter((index) => index >= 0);
  const selected = options.findIndex((option) => option.value === value);
  const tabStop = selected >= 0 && !options[selected].disabled ? selected : (enabled[0] ?? -1);
  const columns = stack
    ? "grid-cols-1 sm:grid-cols-2"
    : options.length <= 2
      ? "grid-cols-2"
      : options.length === 3
        ? "grid-cols-1 sm:grid-cols-3"
        : "grid-cols-2 sm:grid-cols-3";

  function move(event: KeyboardEvent<HTMLButtonElement>, index: number) {
    const position = enabled.indexOf(index);
    const last = enabled.length - 1;
    const target =
      event.key === "ArrowRight" || event.key === "ArrowDown"
        ? enabled[position >= last ? 0 : position + 1]
        : event.key === "ArrowLeft" || event.key === "ArrowUp"
          ? enabled[position <= 0 ? last : position - 1]
          : event.key === "Home"
            ? enabled[0]
            : event.key === "End"
              ? enabled[last]
              : undefined;
    if (target === undefined) return;
    event.preventDefault();
    refs.current[target]?.focus();
    onChange(options[target].value);
  }

  return (
    <div role="radiogroup" aria-label={labelledBy ? undefined : label} aria-labelledby={labelledBy} className={`grid gap-2 ${columns}`}>
      {options.map((option, index) => {
        const checked = index === selected;
        return (
          <button
            key={option.value}
            ref={(element) => {
              refs.current[index] = element;
            }}
            type="button"
            role="radio"
            aria-checked={checked}
            disabled={option.disabled}
            tabIndex={index === tabStop ? 0 : -1}
            onClick={() => onChange(option.value)}
            onKeyDown={(event) => move(event, index)}
            className="flex min-h-11 min-w-0 flex-col items-start justify-center rounded-2xl px-4 py-2 text-start disabled:opacity-50"
            style={{
              background: checked ? "color-mix(in srgb, var(--primary) 14%, var(--panel))" : "var(--panel-raised)",
              border: `1px solid ${checked ? "var(--primary)" : "var(--border)"}`,
              color: "var(--text)",
            }}
          >
            <span className="max-w-full text-sm font-bold [overflow-wrap:anywhere]">{option.label}</span>
            {option.hint ? (
              <span className="max-w-full text-xs [overflow-wrap:anywhere]" style={{ color: "var(--text-soft)" }}>
                {option.hint}
              </span>
            ) : null}
          </button>
        );
      })}
    </div>
  );
}

/** A yes/no question as a labelled checkbox row, with an optional hint under it. */
export function CheckRow({
  checked,
  onChange,
  children,
  hint,
}: {
  checked: boolean;
  onChange: (checked: boolean) => void;
  children: ReactNode;
  hint?: ReactNode;
}) {
  return (
    <label className="flex min-h-11 items-center gap-3 text-sm font-semibold" style={{ color: "var(--text)" }}>
      <input
        type="checkbox"
        checked={checked}
        onChange={(event) => onChange(event.target.checked)}
        className="h-5 w-5 shrink-0"
        style={{ accentColor: "var(--primary)" }}
      />
      <span>
        {children}
        {hint ? (
          <span className="block text-xs font-normal" style={{ color: "var(--dim)" }}>
            {hint}
          </span>
        ) : null}
      </span>
    </label>
  );
}

/** A group of fields under a visible legend. */
export function FieldGroup({ legend, children }: { legend: string; children: ReactNode }) {
  return (
    <fieldset className="flex min-w-0 flex-col gap-2">
      <legend className="mb-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
        {legend}
      </legend>
      {children}
    </fieldset>
  );
}

/** A short line of help under a field. */
export function Hint({ children, id }: { children: ReactNode; id?: string }) {
  return (
    <p id={id} className="text-xs" style={{ color: "var(--dim)" }}>
      {children}
    </p>
  );
}
