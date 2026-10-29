"use client";

import { Fragment } from "react";

import { useGrid, useGridT } from "./context";
import { hintFor, parseFieldKey, roundWordKey } from "./model";
import s from "./grid.module.css";

/**
 * One quiet line under the tables: what the focused value means (`= 65%`,
 * the tempo spelled out, or the field's error) and two to four tips for that
 * kind of field. Empty while no value field has the caret.
 */
export function HintLine({ focused }: { focused: string | null }) {
  const { plan } = useGrid();
  const { t, msg, unit } = useGridT();
  const hint = hintFor(plan, parseFieldKey(focused), t(`word.${roundWordKey(plan)}`));
  const code = (c: string) => (c.startsWith("tip.") ? t(c) : c);
  return (
    <div className={s.hint} aria-live="polite" data-testid="plan-hint">
      {hint.meaning ? <span className={hint.error ? s.err : s.mean}>{msg(hint.meaning.values?.unit ? { ...hint.meaning, values: { ...hint.meaning.values, unit: unit(String(hint.meaning.values.unit)) } } : hint.meaning)}</span> : null}
      {hint.tips.map(([c, meaning], i) => (
        <Fragment key={c}>
          {hint.meaning || i ? " · " : ""}
          <code>{code(c)}</code> {t(meaning)}
        </Fragment>
      ))}
    </div>
  );
}
