"use client";

import { Fragment, useMemo, useRef, useState, type KeyboardEvent, type ReactNode } from "react";

import { Popover } from "@/components/ui/Popover";
import type { PlanRow } from "@/lib/structured-plan/types";

import { useGrid, useGridT } from "./context";
import { fold, fuzzy, type FuzzyMatch } from "./lib";
import { fieldKey, flagMeasures } from "./model";
import { setRowFields } from "./mutations";
import s from "./grid.module.css";

type Suggestion = { label: string; ref: string | null; used: boolean; marks: FuzzyMatch["marks"] };

/** Names for what the coach typed: this WOD's names first, then the exercise library; typo-tolerant. */
export function rankExerciseNames(query: string, used: string[], catalog: { id: string; label: string; aliases: string[] }[], limit = 7): Suggestion[] {
  const q = query.trim();
  if (!q) return [];
  const seen = new Set<string>();
  const out: (Suggestion & { score: number })[] = [];
  const own = new Set(used.map(fold));
  for (const label of used) {
    const m = fuzzy(q, label);
    if (m) out.push({ label, ref: null, used: true, marks: m.marks, score: m.score + 2 });
  }
  for (const item of catalog) {
    const onLabel = fuzzy(q, item.label);
    const onAlias = onLabel ? null : item.aliases.map((a) => fuzzy(q, a)).find(Boolean);
    const m = onLabel ?? onAlias;
    if (m) out.push({ label: item.label, ref: item.id, used: own.has(fold(item.label)), marks: onLabel?.marks ?? [], score: m.score - (onLabel ? 0 : 1) });
  }
  return out
    .sort((a, b) => b.score - a.score)
    .filter((x) => {
      const key = fold(x.label);
      if (seen.has(key) || x.label === q) return false;
      seen.add(key);
      return true;
    })
    .slice(0, limit);
}

export function Highlight({ text, marks }: { text: string; marks: FuzzyMatch["marks"] }) {
  const parts: ReactNode[] = [];
  let at = 0;
  for (const [a, b] of [...marks].sort((x, y) => x[0] - y[0])) {
    if (a < at) continue;
    parts.push(text.slice(at, a), <mark key={a}>{text.slice(a, b)}</mark>);
    at = b;
  }
  parts.push(text.slice(at));
  return (
    <span>
      {parts.map((p, i) => (
        <Fragment key={i}>{p}</Fragment>
      ))}
    </span>
  );
}

/** The exercise name with fuzzy suggestions (↑ ↓, Enter / Tab picks, Esc closes) and its flag tags. */
export function NameCell({ row }: { row: PlanRow }) {
  const { write, catalog, usedNames } = useGrid();
  const { t } = useGridT();
  const inputRef = useRef<HTMLInputElement>(null);
  const [query, setQuery] = useState<string | null>(null);
  const [active, setActive] = useState(0);
  const items = useMemo(
    () => (query === null ? [] : rankExerciseNames(query, usedNames.filter((n) => n !== row.name), catalog)),
    [query, usedNames, catalog, row.name],
  );
  const open = items.length > 0;

  if (row.kind === "rest") {
    return (
      <span className={s.restLabel} data-key={fieldKey.name(row.id)} tabIndex={-1}>
        {t("rest")}
      </span>
    );
  }

  const pick = (it: Suggestion) => {
    const ref = it.ref ?? catalog.find((c) => fold(c.label) === fold(it.label))?.id ?? null;
    write((plan) => setRowFields(plan, row.id, { name: it.label, exerciseRef: ref }));
    setQuery(null);
  };

  const onKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (!open) return;
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      event.stopPropagation();
      setActive((i) => (i + (event.key === "ArrowDown" ? 1 : -1) + items.length) % items.length);
    } else if ((event.key === "Enter" || event.key === "Tab") && !event.shiftKey && !event.altKey) {
      const it = items[active];
      if (!it) return;
      if (event.key === "Enter") {
        event.preventDefault();
        event.stopPropagation();
      }
      pick(it);
    }
  };

  const listId = `plan-names-${row.id}`;
  return (
    <span className={s.nm}>
      <input
        ref={inputRef}
        className={s.name}
        data-key={fieldKey.name(row.id)}
        data-testid={`plan-name-${row.id}`}
        value={row.name}
        placeholder={t("name.placeholder")}
        aria-label={t("name.placeholder")}
        role="combobox"
        aria-expanded={open}
        aria-controls={open ? listId : undefined}
        aria-autocomplete="list"
        aria-activedescendant={open ? `${listId}-${active}` : undefined}
        autoComplete="off"
        spellCheck={false}
        onChange={(event) => {
          const name = event.target.value;
          write((plan) => setRowFields(plan, row.id, { name, exerciseRef: null }), { typing: true });
          setQuery(name);
          setActive(0);
        }}
        onBlur={() => setQuery(null)}
        onKeyDown={onKeyDown}
      />
      {flagMeasures(row).map((k) => (
        <span key={k} className={s.tag}>
          {t(`tag.${k}`)}
        </span>
      ))}
      <Popover anchorRef={inputRef} open={open} onClose={() => setQuery(null)} role="listbox" id={listId} ariaLabel={t("name.suggestions")} className={s.pop} restoreFocus={false}>
        {items.map((it, i) => (
          <div
            key={it.label}
            id={`${listId}-${i}`}
            role="option"
            aria-selected={i === active}
            className={s.opt}
            onMouseDown={(event) => {
              event.preventDefault();
              pick(it);
            }}
          >
            <Highlight text={it.label} marks={it.marks} />
            {it.used ? <small>{t("name.inWod")}</small> : null}
          </div>
        ))}
      </Popover>
    </span>
  );
}
