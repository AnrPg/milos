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

  function increment() {
    const next = value + 1;
    onChange(max !== undefined ? Math.min(max, next) : next);
  }

  function decrement() {
    onChange(Math.max(min, value - 1));
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
        value={value}
        onChange={(event) => onChange(Math.max(min, Number.parseInt(event.target.value, 10) || min))}
        onFocus={() => setShowArrows(true)}
        onBlur={() => setShowArrows(false)}
        className={(width) + " bg-transparent text-center text-sm font-semibold outline-none"}
        style={{ color: "var(--text)" }}
        min={min}
        max={max}
      />
    </div>
  );
}
