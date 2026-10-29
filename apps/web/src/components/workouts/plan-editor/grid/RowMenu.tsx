"use client";

import { useEffect, useMemo, useRef, useState, type KeyboardEvent, type RefObject } from "react";

import { Popover } from "@/components/ui/Popover";
import type { PlanMeasure, PlanStructureKind } from "@/lib/structured-plan/types";

import { useGridActions } from "./actions";
import { SHORTCUT, useGrid, useGridT, type PickerState } from "./context";
import { MEASURE_KEYS, flowStructs, fuzzy, measureAliases, type FuzzyMatch } from "./lib";
import { canPerRound, findRow, structureOfRow } from "./mutations";
import { Highlight } from "./NameCell";
import s from "./grid.module.css";

type Item = { id: string; label: string; hint: string; alias?: string; run: () => void };

/**
 * The one popover of the grid: the row's ⋯ menu (Alt+M) and the two lists
 * it leads to, set structure (Alt+T) and parameter (Alt+P). Typing filters
 * with the same fuzzy match as everywhere; ↑ ↓ Enter pick; Esc or a click
 * outside closes and gives the caret back.
 */
export function RowMenu({ picker, onClose }: { picker: PickerState; onClose: (refocus: boolean) => void }) {
  const { plan } = useGrid();
  const { t, core, kbd } = useGridT();
  const act = useGridActions();
  const [mode, setMode] = useState(picker.mode);
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const anchorRef = useMemo<RefObject<HTMLElement | null>>(() => ({ current: picker.anchor }), [picker.anchor]);
  const filterRef = useRef<HTMLInputElement>(null);

  // The popover stays hidden until it is placed, so `autoFocus` alone misses
  // and the caret stays in the cell (Alt+P then types into the value): focus
  // the filter as soon as it can take focus, and again on a mode switch.
  useEffect(() => {
    let frame = 0;
    let tries = 0;
    const grab = () => {
      const input = filterRef.current;
      if (!input) return;
      input.focus();
      if (document.activeElement !== input && tries++ < 10) frame = requestAnimationFrame(grab);
    };
    grab();
    return () => cancelAnimationFrame(frame);
  }, [mode]);

  const at = findRow(plan, picker.rowId);
  const row = at?.row;

  const items = ((): Item[] => {
    if (!row || !at) return [];
    const done = (fn: () => void) => () => {
      onClose(false);
      fn();
    };
    if (mode === "struct") {
      const current = structureOfRow(plan, row.id)?.kind;
      return flowStructs(plan.flow).map((k: PlanStructureKind) => ({
        id: k,
        label: core(`struct.${k}`),
        hint: k === current ? `✓ ${core(`structHint.${k}`)}` : core(`structHint.${k}`),
        run: done(() => act.setStruct(row.id, k)),
      }));
    }
    if (mode === "measure") {
      const have = new Set(row.extra ?? []);
      return MEASURE_KEYS.filter((k) => !have.has(k)).map((k: PlanMeasure) => ({
        id: k,
        label: core(`measure.${k}`),
        hint: t(`measureHint.${k}`),
        alias: measureAliases(k),
        run: done(() => act.addMeasure(row.id, k)),
      }));
    }
    const ex = row.kind === "ex";
    const list: (Item | null)[] = [
      ex && flowStructs(plan.flow).length ? { id: "struct", label: t("menu.struct"), hint: t("menu.withKey", { key: kbd(SHORTCUT.struct), hint: t("menu.structHint") }), run: () => switchTo("struct") } : null,
      ex ? { id: "measure", label: t("menu.measure"), hint: t("menu.withKey", { key: kbd(SHORTCUT.measure), hint: t("menu.measureHint") }), run: () => switchTo("measure") } : null,
      ex && canPerRound(plan, at.b)
        ? { id: "perRound", label: row.perRound ? t("menu.sameEachRound") : t("menu.perRound"), hint: kbd(SHORTCUT.perRound), run: done(() => act.togglePerRound(row.id)) }
        : null,
      ex ? { id: "note", label: row.note ? t("menu.note") : t("menu.addNote"), hint: kbd(SHORTCUT.note), run: done(() => act.note(row.id)) } : null,
      at.i > 0 || row.group
        ? { id: "superset", label: row.group ? t("menu.unsuperset") : t("menu.superset"), hint: kbd(SHORTCUT.superset), run: done(() => act.toggleSuperset(row.id)) }
        : null,
      { id: "rest", label: t("menu.restAfter"), hint: kbd(SHORTCUT.rest), run: done(() => act.addRow({ afterId: row.id }, "rest")) },
      ...(row.extra ?? []).map((k) => ({
        id: `drop-${k}`,
        label: t("menu.remove", { measure: core(`measure.${k}`) }),
        hint: "",
        run: done(() => act.dropMeasure(row.id, k)),
      })),
      { id: "delete", label: t("menu.delete"), hint: t("menu.deleteHint"), run: done(() => act.deleteRow(row.id)) },
    ];
    return list.filter((x): x is Item => Boolean(x));
  })();

  function switchTo(next: PickerState["mode"]) {
    setMode(next);
    setQuery("");
    setActive(0);
  }

  const shown: (Item & { marks: FuzzyMatch["marks"] })[] = query
    ? items
        .map((it) => {
          const onLabel = fuzzy(query, it.label);
          const m = onLabel ?? fuzzy(query, `${it.alias ?? ""} ${it.hint}`);
          return m ? { ...it, marks: onLabel?.marks ?? [], score: m.score + (onLabel ? 1 : 0) } : null;
        })
        .filter((x): x is Item & { marks: FuzzyMatch["marks"]; score: number } => Boolean(x))
        .sort((a, b) => b.score - a.score)
    : items.map((it) => ({ ...it, marks: [] }));

  const onKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      if (shown.length) setActive((i) => (i + (event.key === "ArrowDown" ? 1 : -1) + shown.length) % shown.length);
    } else if (event.key === "Enter") {
      event.preventDefault();
      shown[active]?.run();
    } else if (event.key === "Backspace" && !query && mode !== "menu" && picker.mode === "menu") {
      event.preventDefault();
      switchTo("menu");
    }
    event.stopPropagation();
  };

  const listId = ["plan-menu", picker.rowId].join("-");
  const title = mode === "struct" ? t("menu.structTitle") : mode === "measure" ? t("menu.measureTitle") : null;
  return (
    <Popover anchorRef={anchorRef} open onClose={() => onClose(true)} role="dialog" ariaLabel={title ?? t("menu.button")} className={s.pop} align="end" minWidth={260} restoreFocus={false}>
      <div data-testid="plan-row-menu" data-mode={mode}>
        {title ? <div className={s.popTitle}>{title}</div> : null}
        <input
          ref={filterRef}
          className={s.popFilter}
          autoFocus
          value={query}
          placeholder={t("menu.filter")}
          aria-label={t("menu.filter")}
          role="combobox"
          aria-expanded
          aria-controls={listId}
          aria-activedescendant={shown[active] ? optionId(listId, shown[active].id) : undefined}
          onChange={(event) => {
            setQuery(event.target.value);
            setActive(0);
          }}
          onKeyDown={onKeyDown}
        />
        <div role="listbox" id={listId}>
          {shown.length ? (
            shown.map((it, i) => (
              <div
                key={it.id}
                id={optionId(listId, it.id)}
                role="option"
                aria-selected={i === active}
                data-item={it.id}
                className={s.opt}
                onMouseDown={(event) => {
                  event.preventDefault();
                  it.run();
                }}
              >
                <Highlight text={it.label} marks={it.marks} />
                <small>{it.hint}</small>
              </div>
            ))
          ) : (
            <div className={s.opt} aria-disabled>
              <span>{t("menu.nothing")}</span>
              <small>{t("menu.nothingHint")}</small>
            </div>
          )}
        </div>
      </div>
    </Popover>
  );
}

const optionId = (listId: string, itemId: string) => [listId, itemId].join("-");
