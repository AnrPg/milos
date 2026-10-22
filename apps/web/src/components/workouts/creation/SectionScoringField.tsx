"use client";

import { useEffect, useId, useMemo, useRef, useState, type KeyboardEvent } from "react";

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

/** One score field while the coach edits it; `kind` is null until a paradigm is known. */
type Row = { id: string; text: string; kind: ScoreKind | null };

let rowSeed = 0;
const rowId = () => `score-row-${(rowSeed += 1)}`;

/** The paradigm whose name the text is, if any («Reps», «Χρόνος»…). */
function canonicalKind(text: string, kindLabels: Record<ScoreKind, string>): ScoreKind | null {
  const typed = text.trim().toLowerCase();
  return SCORE_KINDS.find((kind) => kind !== "custom" && kindLabels[kind].toLowerCase() === typed) ?? null;
}

function rowsFrom(metrics: SectionMetric[]): Row[] {
  return metrics.length > 0
    ? metrics.map((metric) => ({ id: rowId(), text: metric.label, kind: metric.kind }))
    : [{ id: rowId(), text: "", kind: null }];
}

/** The metrics the rows describe: filled rows only, in order. */
function metricsFrom(rows: Row[], kindLabels: Record<ScoreKind, string>): SectionMetric[] {
  return rows.flatMap((row) => {
    const label = row.text.trim().slice(0, MAX_METRIC_LABEL_LENGTH);
    if (!label) return [];
    const kind = canonicalKind(label, kindLabels) ?? row.kind ?? inferScoreKind(label, kindLabels);
    return [{ key: metricKey(label, kind), label, kind }];
  });
}

/**
 * ADR-180: «This section is scored by» on a text section. Each score field
 * picks a paradigm (rounds, reps, time, load, calories, distance) from a
 * dropdown that filters fuzzily as the coach types; a name of the coach's own
 * is kept as a custom score. «+» adds one more score field, since one section
 * may be scored several ways (reps for one part, load for another). After the
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
  const labelId = useId();
  const [rows, setRows] = useState<Row[]>(() => rowsFrom(metrics));
  const [focusRow, setFocusRow] = useState<string | null>(null);

  function update(next: Row[]) {
    setRows(next);
    onChange(metricsFrom(next, kindLabels));
  }

  function addRow() {
    if (rows.length >= MAX_SECTION_METRICS) return;
    const row = { id: rowId(), text: "", kind: null };
    setRows([...rows, row]);
    setFocusRow(row.id);
  }

  function removeRow(id: string) {
    const next = rows.filter((row) => row.id !== id);
    update(next.length > 0 ? next : [{ id: rowId(), text: "", kind: null }]);
  }

  return (
    <div
      className="mt-3 rounded-xl border p-3"
      style={{ borderColor: invalid ? "var(--danger)" : "var(--border)", background: "var(--panel)" }}
      role="group"
      aria-labelledby={labelId}
    >
      <p id={labelId} className="text-xs font-bold" style={{ color: "var(--text-soft)" }}>
        {i18n("sectionScoredByLabel")}
      </p>

      <ul className="mt-2 space-y-2">
        {rows.map((row, index) => (
          <ScoreRow
            key={row.id}
            row={row}
            number={index + 1}
            kindLabels={kindLabels}
            taken={metricsFrom(
              rows.filter((other) => other.id !== row.id),
              kindLabels,
            )}
            autoFocus={focusRow === row.id}
            onChange={(patch) => update(rows.map((item) => (item.id === row.id ? { ...item, ...patch } : item)))}
            onRemove={() => removeRow(row.id)}
          />
        ))}
      </ul>

      {rows.length < MAX_SECTION_METRICS ? (
        <button
          type="button"
          onClick={addRow}
          disabled={rows.some((row) => !row.text.trim())}
          className="mt-2 inline-flex min-h-9 items-center gap-1.5 rounded-full px-3 text-xs font-bold disabled:opacity-40"
          style={{ color: "var(--primary)", border: "1px dashed var(--primary)" }}
        >
          <span aria-hidden="true">+</span>
          {i18n("addScoreMetric")}
        </button>
      ) : null}

      {invalid ? (
        <p className="mt-1 text-xs font-semibold" style={{ color: "var(--danger)" }}>
          {i18n("textSectionScoringInvalid")}
        </p>
      ) : null}
    </div>
  );
}

function ScoreRow({
  row,
  number,
  kindLabels,
  taken,
  autoFocus,
  onChange,
  onRemove,
}: {
  row: Row;
  number: number;
  kindLabels: Record<ScoreKind, string>;
  taken: SectionMetric[];
  autoFocus: boolean;
  onChange: (patch: Partial<Row>) => void;
  onRemove: () => void;
}) {
  const i18n = useUiTranslations();
  const listId = useId();
  const inputRef = useRef<HTMLInputElement>(null);
  const [open, setOpen] = useState(false);
  const [highlight, setHighlight] = useState(0);
  const custom = row.text.trim() !== "" && canonicalKind(row.text, kindLabels) === null;

  useEffect(() => {
    if (autoFocus) inputRef.current?.focus();
  }, [autoFocus]);

  // The paradigms matching what was typed, best first; ones another field
  // already uses go last. Showing them all while the field is empty.
  const options = useMemo(() => {
    const typed = canonicalKind(row.text, kindLabels) ? "" : row.text.trim();
    return suggestScoreKinds(typed, kindLabels, taken);
  }, [row.text, kindLabels, taken]);

  // A paradigm another field already uses gets a number («Reps 2»), so a
  // section can count reps for two parts separately.
  function choose(kind: ScoreKind) {
    const used = new Set(taken.map((metric) => metric.key));
    let text = kindLabels[kind];
    for (let copy = 2; used.has(metricKey(text, kind)); copy += 1) text = `${kindLabels[kind]} ${copy}`;
    onChange({ text, kind });
    setOpen(false);
  }

  function onKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      setOpen(true);
      const step = event.key === "ArrowDown" ? 1 : -1;
      setHighlight((current) => (options.length ? (current + step + options.length) % options.length : 0));
      event.preventDefault();
    } else if (event.key === "Enter") {
      if (open && options[highlight]) choose(options[highlight]);
      else setOpen(false);
      event.preventDefault();
    } else if (event.key === "Escape") {
      setOpen(false);
    }
  }

  const label = i18n("scoreFieldLabel", { number });

  return (
    <li className="relative flex flex-wrap items-center gap-2">
      <input
        ref={inputRef}
        role="combobox"
        aria-label={label}
        aria-expanded={open && options.length > 0}
        aria-controls={listId}
        aria-autocomplete="list"
        aria-activedescendant={open && options[highlight] ? `${listId}-${options[highlight]}` : undefined}
        className="min-w-0 flex-1 basis-40 rounded-xl border px-3 py-2 text-sm outline-none"
        style={{ background: "var(--card)", borderColor: "var(--dim)", color: "var(--text)" }}
        value={row.text}
        maxLength={MAX_METRIC_LABEL_LENGTH}
        placeholder={i18n("sectionScoredByPlaceholder")}
        onChange={(event) => {
          onChange({ text: event.target.value, kind: null });
          setOpen(true);
          setHighlight(0);
        }}
        onFocus={() => setOpen(true)}
        onClick={() => setOpen(true)}
        onBlur={() => setOpen(false)}
        onKeyDown={onKeyDown}
      />
      {/* What a name of the coach's own counts; hidden while choosing from the list. */}
      {custom && !open ? (
        <select
          aria-label={i18n("scoreMetricKindLabel", { label: row.text.trim() })}
          value={row.kind ?? inferScoreKind(row.text, kindLabels)}
          onChange={(event) => onChange({ kind: event.target.value as ScoreKind })}
          className="rounded-xl border px-2 py-2 text-xs font-semibold outline-none"
          style={{ background: "var(--card)", borderColor: "var(--dim)", color: "var(--muted)" }}
        >
          {SCORE_KINDS.map((kind) => (
            <option key={kind} value={kind}>
              {kindLabels[kind]}
            </option>
          ))}
        </select>
      ) : null}
      <button
        type="button"
        aria-label={i18n("removeScoreField", { number })}
        title={i18n("removeScoreField", { number })}
        onClick={onRemove}
        className="grid h-9 w-9 shrink-0 place-items-center rounded-lg text-sm font-bold"
        style={{ color: "var(--text-soft)", border: "1px solid var(--border)" }}
      >
        ×
      </button>
      {open && options.length > 0 ? (
        <ul
          id={listId}
          role="listbox"
          aria-label={label}
          className="absolute inset-x-0 top-full z-(--z-popover) mt-1 max-h-56 overflow-y-auto rounded-xl border py-1 shadow-lg"
          style={{ background: "var(--card)", borderColor: "var(--border)" }}
        >
          {options.map((kind, index) => (
            <li
              key={kind}
              id={`${listId}-${kind}`}
              role="option"
              aria-selected={index === highlight}
              // Keeps focus in the input so the list stays open while choosing.
              onMouseDown={(event) => event.preventDefault()}
              onClick={() => choose(kind)}
              onMouseEnter={() => setHighlight(index)}
              className="cursor-pointer px-3 py-2 text-sm"
              style={{ background: index === highlight ? "var(--panel)" : "transparent", color: "var(--text)" }}
            >
              {kindLabels[kind]}
            </li>
          ))}
        </ul>
      ) : null}
    </li>
  );
}
