"use client";

import { useState, type CSSProperties, type InputHTMLAttributes } from "react";

import type { Parsed } from "@/lib/structured-wod/quantity";

type Props<T> = Omit<InputHTMLAttributes<HTMLInputElement>, "value" | "onChange" | "type"> & {
  value: T | null;
  parse: (text: string) => Parsed<T>;
  format: (value: T | null) => string;
  onCommit: (value: T | null) => void;
  /** Said under the field (as its description) while what was typed cannot be read. */
  invalidText: string;
  fieldStyle?: CSSProperties;
};

/**
 * ADR-270: a quantity typed as text ("10", "30s", "70%"). Each change that
 * reads as a valid amount is saved at once; while the text cannot be read
 * the field turns red, says why, and the last good value stays. On leaving
 * the field it shows the value in its usual form again.
 */
export function QuantityField<T>({ value, parse, format, onCommit, invalidText, fieldStyle, className, onFocus, onBlur, ...inputProps }: Props<T>) {
  const [draft, setDraft] = useState<string | null>(null);
  const [shown, setShown] = useState(value);
  // The value changed from outside while the field is open (undo, another
  // field): show the new value instead of the coach's old text.
  if (JSON.stringify(shown) !== JSON.stringify(value)) {
    setShown(value);
    if (draft !== null && JSON.stringify(parse(draft)) !== JSON.stringify(value)) setDraft(format(value));
  }
  const invalid = draft !== null && parse(draft) === "invalid";

  return (
    <input
      {...inputProps}
      type="text"
      inputMode="text"
      autoComplete="off"
      spellCheck={false}
      aria-invalid={invalid || undefined}
      title={invalid ? invalidText : inputProps.title}
      value={draft ?? format(value)}
      className={className}
      style={{ ...fieldStyle, borderColor: invalid ? "var(--danger)" : fieldStyle?.borderColor }}
      onFocus={(event) => {
        setDraft(format(value));
        onFocus?.(event);
      }}
      onChange={(event) => {
        const text = event.target.value;
        setDraft(text);
        const next = parse(text);
        if (next !== "invalid") onCommit(next);
      }}
      onBlur={(event) => {
        setDraft(null);
        onBlur?.(event);
      }}
    />
  );
}
