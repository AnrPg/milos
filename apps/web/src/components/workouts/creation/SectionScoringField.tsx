"use client";

import { useId, useMemo, useState, type KeyboardEvent } from "react";

import { useUiTranslations } from "@/i18n/ui";
import {
  MAX_METRIC_LABEL_LENGTH,
  MAX_SECTION_METRICS,
  SCORE_KINDS,
  inferScoreKind,
  metricKey,
  suggestScoreKinds,
  type ScoreKind,
  type SectionMetric,
} from "@/lib/text-sections";

export function useScoreKindLabels(): Record<ScoreKind, string> {
  const i18n = useUiTranslations();
  return useMemo(
    () => Object.fromEntries(SCORE_KINDS.map((kind) => [kind, i18n(`scoreKind_${kind}`)])) as Record<ScoreKind, string>,
    [i18n],
  );
}

type Option = { id: string; label: string; kind: ScoreKind; custom: boolean };

/**
 * ADR-179: «This section is scored by» on a text section. The coach types
 * what the section counts; live suggestions offer the common paradigms
 * (rounds, reps, time, load, calories, distance) and «+» adds the typed name
 * as its own score, its kind guessed and changeable on the chip. After the
 * workout athletes get one named field per score.
 */
export function SectionScoringField({
  metrics,
  invalid,
  onChange,
}: {
  metrics: SectionMetric[];
  invalid: boolean;
  onChange: (metrics: SectionMetric[]) => void;
}) {
  const i18n = useUiTranslations();
  const kindLabels = useScoreKindLabels();
  const listId = useId();
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState(false);
  const [highlight, setHighlight] = useState(0);
  const full = metrics.length >= MAX_SECTION_METRICS;
  const takenKeys = new Set(metrics.map((metric) => metricKey(metric.label, metric.kind)));

  const options: Option[] = useMemo(() => {
    const typed = query.trim().slice(0, MAX_METRIC_LABEL_LENGTH);
    const suggestions = suggestScoreKinds(typed, kindLabels, metrics).map((kind) => ({
      id: `kind-${kind}`,
      label: kindLabels[kind],
      kind,
      custom: false,
    }));
    const exact = suggestions.some((option) => option.label.toLowerCase() === typed.toLowerCase());
    const custom: Option[] =
      typed && !exact ? [{ id: "custom", label: typed, kind: inferScoreKind(typed, kindLabels), custom: true }] : [];
    return [...custom, ...suggestions].filter((option) => !takenKeys.has(metricKey(option.label, option.kind)));
    // takenKeys derives from metrics.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query, kindLabels, metrics]);

  function add(option: Option | undefined) {
    if (!option || full) return;
    onChange([...metrics, { key: metricKey(option.label, option.kind), label: option.label, kind: option.kind }]);
    setQuery("");
    setHighlight(0);
  }

  function addTyped() {
    add(options.find((option) => option.custom) ?? options[0]);
  }

  function onKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      setOpen(true);
      const step = event.key === "ArrowDown" ? 1 : -1;
      setHighlight((current) => (options.length ? (current + step + options.length) % options.length : 0));
      event.preventDefault();
    } else if (event.key === "Enter") {
      if (open && options[highlight]) add(options[highlight]);
      else addTyped();
      event.preventDefault();
    } else if (event.key === "Escape") {
      setOpen(false);
    }
  }

  return (
    <div className="mt-3 rounded-xl border p-3" style={{ borderColor: invalid ? "var(--danger)" : "var(--border)", background: "var(--panel)" }}>
      <label htmlFor={`${listId}-input`} className="text-xs font-bold" style={{ color: "var(--text-soft)" }}>
        {i18n("sectionScoredByLabel")}
      </label>

      {metrics.length > 0 ? (
        <ul className="mt-2 flex flex-wrap gap-2" aria-label={i18n("sectionScoredByLabel")}>
          {metrics.map((metric, index) => (
            <li
              key={`${metric.key}-${index}`}
              className="flex min-h-9 items-center gap-1 rounded-full ps-3 pe-1 text-xs font-bold"
              style={{ background: "var(--card)", border: "1px solid var(--border)", color: "var(--text)" }}
            >
              <span className="max-w-[12rem] truncate">{metric.label}</span>
              <select
                aria-label={i18n("scoreMetricKindLabel", { label: metric.label })}
                value={metric.kind}
                onChange={(event) =>
                  onChange(metrics.map((item, at) => (at === index ? { ...item, kind: event.target.value as ScoreKind } : item)))
                }
                className="rounded-full border-0 bg-transparent py-1 text-xs font-semibold outline-none"
                style={{ color: "var(--muted)" }}
              >
                {SCORE_KINDS.map((kind) => (
                  <option key={kind} value={kind}>
                    {kindLabels[kind]}
                  </option>
                ))}
              </select>
              <button
                type="button"
                aria-label={i18n("removeScoreMetric", { label: metric.label })}
                title={i18n("removeScoreMetric", { label: metric.label })}
                onClick={() => onChange(metrics.filter((_, at) => at !== index))}
                className="grid h-7 w-7 place-items-center rounded-full"
                style={{ color: "var(--text-soft)" }}
              >
                ×
              </button>
            </li>
          ))}
        </ul>
      ) : null}

      {full ? null : (
        <div className="relative mt-2 flex gap-2">
          <input
            id={`${listId}-input`}
            role="combobox"
            aria-expanded={open && options.length > 0}
            aria-controls={listId}
            aria-autocomplete="list"
            aria-activedescendant={open && options[highlight] ? `${listId}-${options[highlight].id}` : undefined}
            className="min-w-0 flex-1 rounded-xl border px-3 py-2 text-sm outline-none"
            style={{ background: "var(--card)", borderColor: "var(--dim)", color: "var(--text)" }}
            value={query}
            maxLength={MAX_METRIC_LABEL_LENGTH}
            placeholder={i18n("sectionScoredByPlaceholder")}
            onChange={(event) => {
              setQuery(event.target.value);
              setOpen(true);
              setHighlight(0);
            }}
            onFocus={() => setOpen(true)}
            onBlur={() => setOpen(false)}
            onKeyDown={onKeyDown}
          />
          <button
            type="button"
            aria-label={i18n("addScoreMetric")}
            title={i18n("addScoreMetric")}
            disabled={!query.trim()}
            onClick={addTyped}
            className="grid h-10 w-10 shrink-0 place-items-center rounded-xl text-lg font-black disabled:opacity-40"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            +
          </button>
          {open && options.length > 0 ? (
            <ul
              id={listId}
              role="listbox"
              className="absolute inset-x-0 top-full z-(--z-popover) mt-1 max-h-56 overflow-y-auto rounded-xl border py-1 shadow-lg"
              style={{ background: "var(--card)", borderColor: "var(--border)" }}
            >
              {options.map((option, index) => (
                <li
                  key={option.id}
                  id={`${listId}-${option.id}`}
                  role="option"
                  aria-selected={index === highlight}
                  // Keeps focus in the input so the list stays open while choosing.
                  onMouseDown={(event) => event.preventDefault()}
                  onClick={() => add(option)}
                  onMouseEnter={() => setHighlight(index)}
                  className="flex cursor-pointer items-center justify-between gap-3 px-3 py-2 text-sm"
                  style={{
                    background: index === highlight ? "var(--panel)" : "transparent",
                    color: "var(--text)",
                  }}
                >
                  <span className="truncate">{option.custom ? i18n("addScoreMetricNamed", { label: option.label }) : option.label}</span>
                  {option.custom ? (
                    <span className="shrink-0 text-xs" style={{ color: "var(--muted)" }}>
                      {kindLabels[option.kind]}
                    </span>
                  ) : null}
                </li>
              ))}
            </ul>
          ) : null}
        </div>
      )}

      {invalid ? (
        <p className="mt-1 text-xs font-semibold" style={{ color: "var(--danger)" }}>
          {i18n("textSectionScoringInvalid")}
        </p>
      ) : null}
    </div>
  );
}
