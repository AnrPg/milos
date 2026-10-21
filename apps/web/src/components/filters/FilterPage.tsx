"use client";

import { useEffect, useId, useRef, type ReactNode } from "react";
import { useTranslations } from "next-intl";

// «Φίλτρα (n)» opens this full-screen page (plan §5a decision 3): one section
// per filter, «Καθαρισμός» and «Δείξε N» pinned at the bottom.

export function FilterPage({
  title,
  resultCount,
  onClose,
  onClear,
  children,
}: {
  title: string;
  /** Unknown for paged lists (Ημερολόγιο): the button then reads «Δείξε». */
  resultCount?: number;
  onClose: () => void;
  onClear: () => void;
  children: ReactNode;
}) {
  const t = useTranslations("Filters");
  const headingId = useId();
  const page = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    page.current?.focus();
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKey);
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = overflow;
      previous?.focus();
    };
  }, [onClose]);

  return (
    <div
      ref={page}
      role="dialog"
      aria-modal="true"
      aria-labelledby={headingId}
      tabIndex={-1}
      className="fixed inset-0 z-[60] flex flex-col outline-none"
      style={{ background: "var(--bg)" }}
    >
      <header className="mx-auto flex w-full max-w-xl items-center gap-2 px-4 pb-2 pt-4">
        <button
          type="button"
          onClick={onClose}
          aria-label={t("back")}
          className="grid h-10 w-10 place-items-center rounded-full text-xl"
          style={{ color: "var(--text)" }}
        >
          <span aria-hidden="true">‹</span>
        </button>
        <h2 id={headingId} className="text-xl font-extrabold" style={{ color: "var(--text)" }}>
          {title}
        </h2>
      </header>

      <div className="flex-1 overflow-y-auto">
        <div className="mx-auto flex w-full max-w-xl flex-col gap-6 px-4 pb-6 pt-2">{children}</div>
      </div>

      <footer
        className="mx-auto grid w-full max-w-xl grid-cols-[1fr_2fr] gap-3 px-4 pb-[max(1rem,env(safe-area-inset-bottom))] pt-3"
        style={{ borderTop: "1px solid var(--border)" }}
      >
        <button
          type="button"
          onClick={onClear}
          className="min-h-12 rounded-2xl text-sm font-bold"
          style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
        >
          {t("clear")}
        </button>
        <button
          type="button"
          onClick={onClose}
          className="min-h-12 rounded-2xl text-sm font-bold"
          style={{ background: "var(--primary)", color: "var(--bg)" }}
        >
          {resultCount === undefined ? t("show") : t("showResults", { count: resultCount })}
        </button>
      </footer>
    </div>
  );
}

export function FilterSection({ label, hint, children }: { label: string; hint?: string; children: ReactNode }) {
  const id = useId();
  return (
    <section aria-labelledby={id} className="flex flex-col gap-2.5">
      <div className="flex items-baseline justify-between gap-3">
        <h3 id={id} className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
          {label}
        </h3>
        {hint ? (
          <span className="text-xs" style={{ color: "var(--dim)" }}>
            {hint}
          </span>
        ) : null}
      </div>
      {children}
    </section>
  );
}

/** Chips that pick one value (`multiple` false) or several. */
export function ChoiceChips<T extends string>({
  options,
  selected,
  multiple,
  onChange,
  ariaLabel,
}: {
  options: Array<{ value: T; label: string }>;
  selected: T[];
  multiple: boolean;
  onChange: (values: T[]) => void;
  ariaLabel: string;
}) {
  return (
    <div role="group" aria-label={ariaLabel} className="flex flex-wrap gap-2">
      {options.map((option) => {
        const on = selected.includes(option.value);
        return (
          <button
            key={option.value}
            type="button"
            aria-pressed={on}
            onClick={() =>
              onChange(
                multiple
                  ? on
                    ? selected.filter((value) => value !== option.value)
                    : [...selected, option.value]
                  : [option.value],
              )
            }
            className="min-h-10 rounded-full px-4 text-sm font-semibold"
            style={{
              background: on ? "color-mix(in srgb, var(--primary) 16%, var(--panel))" : "var(--panel)",
              border: `1px solid ${on ? "var(--primary)" : "var(--border)"}`,
              color: on ? "var(--text)" : "var(--text-soft)",
            }}
          >
            {option.label}
          </button>
        );
      })}
    </div>
  );
}

/** A from–to range with two thumbs (plan §5a decision 5). */
export function RangeSlider({
  min,
  max,
  step,
  value,
  onChange,
  format,
  fromLabel,
  toLabel,
}: {
  min: number;
  max: number;
  step: number;
  value: { from: number; to: number };
  onChange: (value: { from: number; to: number }) => void;
  format: (value: number) => string;
  fromLabel: string;
  toLabel: string;
}) {
  const span = max - min;
  const left = ((value.from - min) / span) * 100;
  const right = ((max - value.to) / span) * 100;

  return (
    <div className="flex flex-col gap-2">
      <p className="self-end font-mono text-sm font-semibold" style={{ color: "var(--text)" }}>
        {format(value.from)} – {format(value.to)}
      </p>
      <div className="relative h-8">
        <div className="absolute inset-x-0 top-3.5 h-1 rounded-full" style={{ background: "var(--border)" }} />
        <div
          className="absolute top-3.5 h-1 rounded-full"
          style={{ left: `${left}%`, right: `${right}%`, background: "var(--primary)" }}
        />
        <input
          type="range"
          aria-label={fromLabel}
          aria-valuetext={format(value.from)}
          min={min}
          max={max}
          step={step}
          value={value.from}
          onChange={(event) => onChange({ from: Math.min(Number(event.target.value), value.to - step), to: value.to })}
          className="milos-range-thumb pointer-events-none absolute inset-x-0 top-0 h-8 w-full appearance-none bg-transparent"
        />
        <input
          type="range"
          aria-label={toLabel}
          aria-valuetext={format(value.to)}
          min={min}
          max={max}
          step={step}
          value={value.to}
          onChange={(event) => onChange({ from: value.from, to: Math.max(Number(event.target.value), value.from + step) })}
          className="milos-range-thumb pointer-events-none absolute inset-x-0 top-0 h-8 w-full appearance-none bg-transparent"
        />
      </div>
      <div className="flex justify-between text-xs" style={{ color: "var(--dim)" }}>
        <span>{format(min)}</span>
        <span>{format(max)}</span>
      </div>
    </div>
  );
}
