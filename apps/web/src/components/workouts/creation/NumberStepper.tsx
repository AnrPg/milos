"use client";


import { useState } from "react";

type Props = {
  value: number;
  onChange: (value: number) => void;
  min?: number;
  max?: number;
  width?: string;
};

export function NumberStepper({ value, onChange, min = 1, max, width = "w-10" }: Props) {
  const [showArrows, setShowArrows] = useState(false);
  const [draft, setDraft] = useState<string | null>(null);
  const text = draft ?? String(value);

  function increment() {
    const next = value + 1;
    const normalized = max !== undefined ? Math.min(max, next) : next;
    setDraft(null);
    onChange(normalized);
  }

  function decrement() {
    const normalized = Math.max(min, value - 1);
    setDraft(null);
    onChange(normalized);
  }

  function commit() {
    const parsed = Number.parseInt(text, 10);
    const bounded = Math.max(min, max === undefined ? parsed : Math.min(max, parsed));
    const normalized = Number.isNaN(bounded) ? min : bounded;
    setDraft(null);
    if (normalized !== value || text.trim() === "") onChange(normalized);
    setShowArrows(false);
  }

  return (
    <div
      className="flex items-center gap-0.5"
      onMouseEnter={() => setShowArrows(true)}
      onMouseLeave={() => setShowArrows(false)}
    >
      <div
        className="flex flex-col"
        style={{
          opacity: showArrows ? 1 : 0,
          transition: "opacity 0.12s",
          pointerEvents: showArrows ? "auto" : "none",
        }}
      >
        <button
          type="button"
          onMouseDown={(event) => event.preventDefault()}
          onClick={increment}
          className="px-0.5 text-xs leading-none"
          style={{ color: "var(--muted)" }}
        >
          ▲
        </button>
        <button
          type="button"
          onMouseDown={(event) => event.preventDefault()}
          onClick={decrement}
          className="px-0.5 text-xs leading-none"
          style={{ color: "var(--muted)" }}
        >
          ▼
        </button>
      </div>
      <input
        type="number"
        value={text}
        onChange={(event) => {
          const next = event.target.value;
          setDraft(next);
          if (next.trim() === "") return;
          const parsed = Number.parseInt(next, 10);
          if (!Number.isNaN(parsed)) onChange(parsed);
        }}
        onFocus={() => {
          setDraft(String(value));
          setShowArrows(true);
        }}
        onBlur={commit}
        className={(width) + " bg-transparent text-center text-sm font-semibold outline-none"}
        style={{ color: "var(--text)" }}
        min={min}
        max={max}
      />
    </div>
  );
}
