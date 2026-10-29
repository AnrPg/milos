"use client";

import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type CSSProperties, type KeyboardEvent } from "react";

import type { PlanSection } from "@/lib/structured-plan/types";

import { useGridActions } from "./actions";
import { GridContext, SHORTCUT, useGrid, useGridT, type GridContextValue, type PickerState } from "./context";
import { HintLine } from "./HintLine";
import { NAV_FIELDS, occurrences, setsRange, totalRounds } from "./lib";
import { attr, blockTitle, parseFieldKey, roundWordKey } from "./model";
import { findRow } from "./mutations";
import { RowMenu } from "./RowMenu";
import { consumeFocus, requestFocus, usePendingFocus, usePlanSection, usePlanWriter, useWodExerciseNames } from "./store-adapter";
import { ExerciseTable, SetTable } from "./Tables";
import { useExerciseCatalog } from "./useExerciseCatalog";
import s from "./grid.module.css";

/** Below this width of the grid itself, every exercise is a card and sets / rounds are rows. */
export const PHONE_MAX_WIDTH = 600;
const BLOCK_COLORS = ["var(--primary)", "var(--success)", "var(--heat)"];

/**
 * ADR-270 step «Ασκήσεις» of one section: the exercise tables of the
 * structured WOD editor (approved mockup v20). Reads and writes the section
 * through the editor store.
 */
export function PlanGrid({ sectionId }: { sectionId: string }) {
  const plan = usePlanSection(sectionId);
  const write = usePlanWriter(sectionId);
  const catalog = useExerciseCatalog();
  const usedNames = useWodExerciseNames();
  const rootRef = useRef<HTMLDivElement>(null);
  const phone = usePhoneLayout(rootRef);
  const pending = usePendingFocus();
  const [focused, setFocused] = useState<string | null>(null);
  const [notesOpen, setNotesOpen] = useState<ReadonlySet<string>>(() => new Set());
  const [picker, setPicker] = useState<PickerState | null>(null);

  // A field asked for (a new row's name, a new measure) gets the caret once it is on screen.
  useEffect(() => {
    if (!pending) return;
    const el = rootRef.current?.querySelector<HTMLElement>(`[data-key="${attr(pending)}"]`);
    if (!el) return;
    el.focus();
    if (el instanceof HTMLInputElement) el.select();
    consumeFocus(pending);
  }, [pending, plan, phone]);

  const ctx = useMemo<GridContextValue | null>(
    () =>
      plan
        ? {
            sectionId,
            plan,
            write,
            phone,
            focusKey: requestFocus,
            notesOpen,
            openNote: (rowId) => setNotesOpen((open) => new Set(open).add(rowId)),
            openPicker: setPicker,
            catalog,
            usedNames,
          }
        : null,
    [sectionId, plan, write, phone, notesOpen, catalog, usedNames],
  );

  const closePicker = useCallback(
    (refocus: boolean) => {
      const back = picker?.returnKey;
      setPicker(null);
      if (refocus && back) requestFocus(back);
      else if (refocus) picker?.anchor.focus();
    },
    [picker],
  );

  if (!ctx || plan?.flow === "rest") return null;
  return (
    <GridContext.Provider value={ctx}>
      <div
        ref={rootRef}
        className={s.root}
        data-layout={phone ? "phone" : "wide"}
        data-testid="plan-grid"
        onFocus={(event) => {
          // Only a field changes the hint line. A button keeps it as it was: on mousedown
          // on «+ Άσκηση» the line emptying would move the button and lose the tap.
          const key = (event.target as HTMLElement).dataset.key;
          if (key) setFocused(key);
        }}
        onBlur={(event) => {
          if (!rootRef.current?.contains(event.relatedTarget as Node | null)) setFocused(null);
        }}
      >
        <GridKeys picker={picker} rootRef={rootRef}>
          {ctx.plan.flow === "sets" ? <SetsFlow /> : <BoxesFlow />}
          {ctx.plan.mods?.interrupt ? <InterruptLane /> : null}
          <HintLine focused={focused} />
          <Footer />
        </GridKeys>
        {picker ? <RowMenu key={`${picker.rowId}:${picker.mode}`} picker={picker} onClose={closePicker} /> : null}
      </div>
    </GridContext.Provider>
  );
}

/** Measures the grid's own width (not the window's), so a narrow editor column gets the phone layout too. */
function usePhoneLayout(ref: React.RefObject<HTMLElement | null>) {
  const [phone, setPhone] = useState(false);
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const measure = () => {
      const width = el.clientWidth;
      // 0 = not laid out (hidden, or a test without layout): keep the wide grid.
      if (width > 0) setPhone(width < PHONE_MAX_WIDTH);
    };
    measure();
    if (typeof ResizeObserver === "undefined") return;
    const observer = new ResizeObserver(measure);
    observer.observe(el);
    return () => observer.disconnect();
  });
  return phone;
}

const colWord = (plan: PlanSection) => roundWordKey(plan);

function SetsFlow() {
  const { plan, phone } = useGrid();
  const { t, msg } = useGridT();
  const act = useGridActions();
  const k = plan.blocks.length;
  const total = totalRounds(plan);
  return (
    <>
      {plan.blocks.map((rows, b) => {
        const occ = occurrences(plan, b);
        const title = msg(blockTitle(plan, b, occ.list, occ.open, total));
        const table = <SetTable key={b} rows={rows} b={b} occ={occ.list} title={title} />;
        if (k <= 1) return table;
        return (
          <div key={b} className={s.gblock} style={{ "--block-color": BLOCK_COLORS[b % 3] } as CSSProperties}>
            {phone ? <div className={`${s.lbl} ${s.blockTitle}`}>{title}</div> : null}
            {table}
            <div className={s.adds}>
              <button type="button" className={s.add} data-testid={`plan-add-exercise-${b}`} onClick={() => act.addRow({ afterId: rows.at(-1)?.id, b })}>
                {t("add.exerciseSets")}
              </button>
            </div>
          </div>
        );
      })}
    </>
  );
}

function BoxesFlow() {
  const { plan } = useGrid();
  const { t, msg, kbd } = useGridT();
  const act = useGridActions();
  const k = plan.blocks.length;
  const total = totalRounds(plan);
  const word = t(`colWord.${colWord(plan)}`);
  return (
    <div className={s.slots}>
      {plan.blocks.map((rows, b) => {
        const occ = occurrences(plan, b);
        return (
          <div key={b} className={s.slot} style={{ "--block-color": BLOCK_COLORS[b % 3] } as CSSProperties} data-testid={`plan-box-${b}`}>
            <div className={s.lbl}>{msg(blockTitle(plan, b, occ.list, occ.open, total))}</div>
            <ExerciseTable rows={rows} b={b} word={word} occ={occ.list} />
            <button
              type="button"
              className={`${s.add} ${s.wide}`}
              data-testid={b === 0 ? "plan-add-exercise" : `plan-add-exercise-${b}`}
              onClick={() => act.addRow({ afterId: rows.at(-1)?.id, b })}
            >
              {k === 1 ? t("add.exercise") : t("add.exerciseHere")}
              {k === 1 ? <kbd className={s.kbd}>{kbd(SHORTCUT.enter)}</kbd> : null}
            </button>
          </div>
        );
      })}
    </div>
  );
}

function InterruptLane() {
  const { plan } = useGrid();
  const { t } = useGridT();
  const act = useGridActions();
  const rows = plan.interrupt ?? [];
  return (
    <div className={s.lane} data-testid="plan-interrupt">
      <div className={s.lbl}>{t("interrupt.title", { every: plan.params.intEvery || "?" })}</div>
      <ExerciseTable rows={rows} b={-1} word={t(`colWord.${colWord(plan)}`)} occ={[1]} />
      <button type="button" className={`${s.add} ${s.wide}`} data-testid="plan-add-exercise-int" onClick={() => act.addRow({ afterId: rows.at(-1)?.id, b: -1 })}>
        {t("add.exerciseInterrupt")}
      </button>
    </div>
  );
}

function Footer() {
  const { plan } = useGrid();
  const { t, kbd } = useGridT();
  const act = useGridActions();
  const k = plan.blocks.length;
  const total = totalRounds(plan);
  const word = colWord(plan);
  const sr = setsRange(plan);
  const cycle = plan.blocks.map((_, i) => i + 1).join(", ");
  const sets = plan.flow === "sets";
  const lastBlock = plan.blocks.length - 1;
  return (
    <>
      {sets && sr.max > sr.min ? <p className={s.uhint}>{t("how.optionalSets", { sets: plan.params.sets ?? "" })}</p> : null}
      {plan.flow === "amrap" ? <p className={s.uhint}>{t("how.amrapMax")}</p> : null}
      <div className={s.adds}>
        {sets ? (
          <button
            type="button"
            className={s.add}
            data-testid="plan-add-exercise"
            onClick={() => act.addRow({ afterId: plan.blocks[lastBlock]?.at(-1)?.id, b: Math.max(0, lastBlock) })}
          >
            {t("add.exercise")}
            <kbd className={s.kbd}>{kbd(SHORTCUT.enter)}</kbd>
          </button>
        ) : null}
        <button type="button" className={s.add} data-testid="plan-add-round" onClick={() => act.addRound()}>
          {t(`add.round.${word}`)}
          <kbd className={s.kbd}>{kbd(SHORTCUT.round)}</kbd>
        </button>
      </div>
      {k > 1 ? <p className={s.uhint}>{k >= total ? t(`how.own.${word}`) : t("how.alternate", { cycle })}</p> : null}
      {k === 1 && plan.flow === "emom" ? <p className={s.uhint}>{t("how.emomOne")}</p> : null}
    </>
  );
}

/**
 * The grid's keyboard: Enter adds a row, ↑ ↓ move between rows in the same
 * column, ⌫ on an empty name deletes the row, and the Alt shortcuts of the
 * row menu. Handled keys are marked `defaultPrevented` so the editor shell's
 * own shortcuts (Esc, Alt+←/→, Mod+Z) leave them alone.
 */
function GridKeys({ picker, rootRef, children }: { picker: PickerState | null; rootRef: React.RefObject<HTMLDivElement | null>; children: React.ReactNode }) {
  const { plan } = useGrid();
  const act = useGridActions();

  const onKeyDown = (e: KeyboardEvent<HTMLDivElement>) => {
    if (picker || e.defaultPrevented) return;
    const target = e.target as HTMLElement;
    const key = target.dataset.key ?? "";
    const mod = e.ctrlKey || e.metaKey;
    const handled = () => {
      e.preventDefault();
      e.stopPropagation();
    };
    if (e.altKey && e.code === "KeyS") {
      handled();
      act.addRound();
      return;
    }
    const rowId = /^(?:r|c):([^:]+)/.exec(key)?.[1];
    const at = rowId ? findRow(plan, rowId) : null;
    if (!at) return;
    const row = at.row;
    const value = target instanceof HTMLInputElement ? target.value : "";

    if (e.altKey && !mod) {
      switch (e.code) {
        case "KeyM":
          handled();
          act.open(row.id, "menu", null, key);
          return;
        case "KeyT":
          if (row.kind !== "ex") return;
          handled();
          act.open(row.id, "struct", null, key);
          return;
        case "KeyP":
          if (row.kind !== "ex") return;
          handled();
          act.open(row.id, "measure", null, key);
          return;
        case "KeyV":
          handled();
          act.togglePerRound(row.id);
          return;
        case "KeyN":
          if (row.kind !== "ex") return;
          handled();
          act.note(row.id);
          return;
        case "KeyG":
          handled();
          act.toggleSuperset(row.id);
          return;
        case "KeyR":
          handled();
          act.addRow({ afterId: row.id }, "rest");
          return;
      }
      return;
    }
    if (mod || e.shiftKey) return;
    if (e.key === "Enter") {
      handled();
      act.addRow({ afterId: row.id });
      return;
    }
    if (e.key === "Backspace" && value === "") {
      if (key.endsWith(":name")) {
        handled();
        act.deleteRow(row.id);
        return;
      }
      const measure = /^r:[^:]+:x:(\w+)$/.exec(key)?.[1];
      if (measure) {
        handled();
        act.dropMeasure(row.id, measure as Parameters<typeof act.dropMeasure>[1]);
      }
      return;
    }
    if (e.key === "ArrowUp" || e.key === "ArrowDown") {
      const next = neighbourField(rootRef.current, target, key, e.key === "ArrowUp" ? -1 : 1);
      if (!next) return;
      handled();
      next.focus();
      next.select();
    }
  };

  return (
    <div onKeyDown={onKeyDown} style={{ display: "contents" }}>
      {children}
    </div>
  );
}

/** The field in the row above / below that sits in the same column (or its first field). */
export function neighbourField(root: HTMLElement | null, from: HTMLElement, key: string, dir: -1 | 1): HTMLInputElement | HTMLTextAreaElement | null {
  if (!root) return null;
  const rows = [...root.querySelectorAll<HTMLElement>("[data-nav-row]")];
  const cur = from.closest<HTMLElement>("[data-nav-row]");
  const next = cur ? rows[rows.indexOf(cur) + dir] : null;
  if (!next) return null;
  const inputs = [...next.querySelectorAll<HTMLInputElement | HTMLTextAreaElement>(NAV_FIELDS)];
  const here = columnOf(key);
  return (
    inputs.find((x) => { const c = columnOf(x.dataset.key); return c.k === here.k && c.col === here.col; }) ??
    inputs.find((x) => columnOf(x.dataset.key).k === here.k) ??
    inputs[0] ??
    null
  );
}

/** Which column a field sits in: its value key (d, l, a measure, name, note) and set / round. */
function columnOf(key: string | undefined): { k: string; col: number | null } {
  const f = parseFieldKey(key);
  if (!f) return { k: "", col: null };
  if (f.kind === "cell") return { k: f.k, col: f.col };
  if (f.kind === "x") return { k: f.k, col: null };
  return { k: f.field === "dose" ? "d" : f.field === "load" ? "l" : f.field, col: null };
}

export default PlanGrid;
