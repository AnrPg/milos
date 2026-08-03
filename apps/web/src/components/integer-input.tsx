"use client";

import { useState, type InputHTMLAttributes } from "react";

type Props = Omit<InputHTMLAttributes<HTMLInputElement>, "onChange" | "value" | "type"> & {
  value: number | null;
  onValueChange: (value: number | null) => void;
  emptyValue?: number | null;
};

export function IntegerInput({ value, onValueChange, emptyValue = null, min, max, onBlur, onFocus, ...props }: Props) {
  const [draft, setDraft] = useState<string | null>(null);
  const text = draft ?? (value == null ? "" : String(value));

  function commit() {
    if (text.trim() === "") {
      onValueChange(emptyValue);
      setDraft(null);
      return;
    }

    const parsed = Number.parseInt(text, 10);
    if (Number.isNaN(parsed)) return;
    const minimum = typeof min === "number" ? min : Number.NEGATIVE_INFINITY;
    const maximum = typeof max === "number" ? max : Number.POSITIVE_INFINITY;
    const next = Math.min(maximum, Math.max(minimum, parsed));
    setDraft(null);
    onValueChange(next);
  }

  return <input {...props} max={max} min={min} type="number" value={text} onChange={(event) => setDraft(event.target.value)} onFocus={(event) => { setDraft(value == null ? "" : String(value)); onFocus?.(event); }} onBlur={(event) => { commit(); onBlur?.(event); }} />;
}
