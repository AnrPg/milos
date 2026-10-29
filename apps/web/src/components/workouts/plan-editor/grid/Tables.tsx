"use client";

import type { CSSProperties } from "react";

import type { PlanRow, PlanSection, PlanUnit } from "@/lib/structured-plan/types";

import { useGrid, useGridT } from "./context";
import { setsRange, structOf, unitsOf } from "./lib-shim";
import {
  attr,
  cellTestId,
  compactField,
  fieldKey,
  lineKeys,
  measureUnit,
  perSummary,
  rowCells,
  tableColumns,
  type ColKey,
  type MeasureKey,
  type RowCells,
} from "./model";
import { canPerRound, setCell, setRowFields, setRowMeasure } from "./mutations";
import { MoreButton, NoteLine, StructHead, hasNote } from "./RowParts";
import { NameCell } from "./NameCell";
import { ValueField } from "./ValueField";
import s from "./grid.module.css";

/** Column / line labels with their unit: "Επαν.", "Φορτίο kg", "RPE /10", "Κράτημα (δευτ.)". */
export function useLabels() {
  const { t, unit } = useGridT();
  const measureHead = (k: MeasureKey) => {
    const u = unit(measureUnit(k));
    const label = t(`measure.${k}`);
    return !u ? label : /^\p{L}/u.test(u) ? `${label} (${u})` : `${label} ${u}`;
  };
  const line = (row: PlanRow, k: ColKey, loadUnit: string | null) =>
    k === "d" ? (row.kind === "rest" ? t("line.rest") : t("line.d")) : k === "l" ? (loadUnit ? t("line.lUnit", { unit: loadUnit }) : t("line.l")) : measureHead(k);
  const column = (k: ColKey) => (k === "d" ? t("col.d") : k === "l" ? t("col.l") : measureHead(k));
  return { measureHead, line, column };
}

/** One set / round column of a row: a field per line (reps, load, measures), in label order. */
function CellFields({ row, col, num, cells, word }: { row: PlanRow; col: number; num: number; cells: RowCells; word: string }) {
  const { write } = useGrid();
  const { msg, unit } = useGridT();
  const labels = useLabels();
  return lineKeys(row).map((k) => {
    const view = cells.views[k]?.[col] ?? { placeholder: "—", display: "", badge: "", error: null, suffix: "" };
    const key = { kind: "cell" as const, rowId: row.id, col, k };
    return (
      <ValueField
        key={k}
        fieldKey={fieldKey.cell(row.id, col, k)}
        testId={cellTestId(key)}
        value={row.cells[col]?.[k] ?? ""}
        view={view}
        errorText={msg(view.error)}
        suffix={unit(view.suffix)}
        ariaLabel={`${word} ${num}: ${labels.line(row, k, cells.loadUnit)}`}
        onChange={(v) => write((p) => setCell(p, row.id, col, k, v), { typing: true })}
      />
    );
  });
}

/**
 * A row's values per set or round. Wide: a labels column, then one column per
 * set / round with the row's lines stacked. Phone: one line per set / round,
 * the row's lines as columns (how workout apps lay out sets).
 */
export function ValuesTable({ row, occ, word, testId }: { row: PlanRow; occ: number[]; word: string; testId?: string }) {
  const { phone } = useGrid();
  const labels = useLabels();
  const cells = rowCells(row, occ.length);
  const keys = lineKeys(row);
  if (phone) {
    return (
      <div className={`${s.gridwrap} ${s.mini} ${s.tall}`} data-testid={testId}>
        <table className={s.grid}>
          <thead>
            <tr>
              <th className={s.setno}>{word}</th>
              {keys.map((k) => (
                <th key={k}>{labels.line(row, k, cells.loadUnit)}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {occ.map((num, i) => (
              <tr key={num} data-nav-row={row.id}>
                <td className={s.setno}>{num}</td>
                {keys.map((k) => (
                  <SingleField key={k} row={row} k={k} col={i} num={num} cells={cells} word={word} />
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    );
  }
  return (
    <div className={`${s.gridwrap} ${s.mini}`} data-testid={testId}>
      <table className={s.grid}>
        <thead>
          <tr>
            <th aria-hidden="true" />
            {occ.map((num) => (
              <th key={num}>{`${word} ${num}`}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          <tr data-nav-row={row.id}>
            <td className={s.labs}>
              {keys.map((k) => (
                <div key={k}>{labels.line(row, k, cells.loadUnit)}</div>
              ))}
            </td>
            {occ.map((num, i) => (
              <td key={num}>
                <div className={s.c}>
                  <CellFields row={row} col={i} num={num} cells={cells} word={word} />
                </div>
              </td>
            ))}
          </tr>
        </tbody>
      </table>
    </div>
  );
}

/** One line of one set / round (phone rows). */
function SingleField({ row, k, col, num, cells, word }: { row: PlanRow; k: ColKey; col: number; num: number; cells: RowCells; word: string }) {
  const { write } = useGrid();
  const { msg, unit } = useGridT();
  const labels = useLabels();
  const view = cells.views[k]?.[col] ?? { placeholder: "—", display: "", badge: "", error: null, suffix: "" };
  return (
    <td>
      <ValueField
        fieldKey={fieldKey.cell(row.id, col, k)}
        testId={cellTestId({ kind: "cell", rowId: row.id, col, k })}
        value={row.cells[col]?.[k] ?? ""}
        view={view}
        errorText={msg(view.error)}
        suffix={unit(view.suffix)}
        ariaLabel={`${word} ${num}: ${labels.line(row, k, cells.loadUnit)}`}
        onChange={(v) => write((p) => setCell(p, row.id, col, k, v), { typing: true })}
      />
    </td>
  );
}

// ── Σετ: rows are exercises, columns are sets ─────────────────────────────

export function SetTable({ rows, b, occ, title }: { rows: PlanRow[]; b: number; occ: number[]; title: string }) {
  const { plan, phone } = useGrid();
  const { t } = useGridT();
  const labels = useLabels();
  const sr = setsRange(plan);
  const word = t("round.set", { list: "" }).trim();
  const units = unitsOf(rows);

  if (phone) {
    return (
      <div className={s.scards} data-testid={`plan-block-${b}`}>
        {units.map((u) => (
          <div key={u.group ?? u.rows[0]!.id} className={s.scards}>
            <StructHead unit={u} />
            {u.rows.map((row) => (
              <div key={row.id} className={s.scard} data-grouped={u.rows.length > 1 ? "" : undefined} data-testid={`plan-row-${row.id}`}>
                <div className={s.scardHead}>
                  <NameCell row={row} />
                  <MoreButton row={row} />
                </div>
                <NoteLine row={row} />
                <ValuesTable row={row} occ={occ} word={word} />
              </div>
            ))}
          </div>
        ))}
      </div>
    );
  }

  const n = occ.length;
  return (
    <div className={s.gridwrap} data-testid={`plan-block-${b}`}>
      <table className={s.grid}>
        <thead>
          <tr>
            <th>{title}</th>
            {occ.map((num) => {
              const optional = num > sr.min;
              return (
                <th key={num} data-optional={optional ? "" : undefined} title={optional ? t("optionalSet", { sets: plan.params.sets ?? "" }) : undefined}>
                  {`${word} ${num}${optional ? "*" : ""}`}
                </th>
              );
            })}
            <th className={s.moreCell} aria-hidden="true" />
          </tr>
        </thead>
        <tbody>
          {units.map((u) => {
            const grouped = u.rows.length > 1;
            return [
              <StructRow key={`h-${u.group ?? u.rows[0]!.id}`} unit={u} span={n + 2} />,
              ...u.rows.map((row) => {
                const cells = rowCells(row, n);
                return (
                  <tr key={row.id} data-nav-row={row.id} data-grouped={grouped ? "" : undefined} data-testid={`plan-row-${row.id}`}>
                    <td className={s.first}>
                      <div className={s.fx}>
                        <div className={s.fname}>
                          <NameCell row={row} />
                          <NoteLine row={row} />
                        </div>
                        <div className={s.labs}>
                          {lineKeys(row).map((k) => (
                            <div key={k}>{labels.line(row, k, cells.loadUnit)}</div>
                          ))}
                        </div>
                      </div>
                    </td>
                    {occ.map((num, i) => (
                      <td key={num}>
                        <div className={s.c}>
                          <CellFields row={row} col={i} num={num} cells={cells} word={word} />
                        </div>
                      </td>
                    ))}
                    <td className={s.moreCell}>
                      <MoreButton row={row} />
                    </td>
                  </tr>
                );
              }),
            ];
          })}
        </tbody>
      </table>
    </div>
  );
}

const isPlain = (plan: PlanSection, u: PlanUnit) => u.rows.length === 1 && structOf(plan, u).kind === "single";

function StructRow({ unit, span }: { unit: PlanUnit; span: number }) {
  const { plan } = useGrid();
  if (isPlain(plan, unit)) return null;
  return (
    <tr className={s.grp}>
      <td colSpan={span}>
        <StructHead unit={unit} />
      </td>
    </tr>
  );
}

// ── other flows: one CSS-grid table per block ────────────────────────────

export function ExerciseTable({ rows, b, word, occ }: { rows: PlanRow[]; b: number; word: string; occ: number[] }) {
  const { plan } = useGrid();
  const cols = tableColumns(rows);
  const labels = useLabels();
  const { t } = useGridT();
  return (
    <div className={s.xt} style={{ "--cols": cols.length } as CSSProperties} data-testid={`plan-block-${b}`}>
      <div className={s.xh} aria-hidden="true">
        <span>{t("head.exercise")}</span>
        {cols.map((k) => (
          <span key={k}>{labels.column(k)}</span>
        ))}
        <span />
      </div>
      {unitsOf(rows).map((u) => [
        !isPlain(plan, u) ? (
          <div key={`h-${u.group ?? u.rows[0]!.id}`} className={s.xg}>
            <StructHead unit={u} />
          </div>
        ) : null,
        ...u.rows.map((row) => <CompactRow key={row.id} row={row} b={b} cols={cols} word={word} occ={occ} grouped={u.rows.length > 1} />),
      ])}
    </div>
  );
}

function CompactRow({ row, b, cols, word, occ, grouped }: { row: PlanRow; b: number; cols: ColKey[]; word: string; occ: number[]; grouped: boolean }) {
  const { plan, write, notesOpen } = useGrid();
  const { t, msg, unit } = useGridT();
  const labels = useLabels();
  const per = row.kind === "ex" && Boolean(row.perRound) && canPerRound(plan, b);
  const has = new Set(row.extra ?? []);
  const cells = cols.map((k) => {
    const label = labels.column(k);
    if (row.kind === "rest") {
      if (k !== "d") return <span key={k} className={s.xv} data-label={label} data-empty="" />;
      const view = compactField(row, "d");
      return (
        <span key={k} className={s.xv} data-label={t("line.rest")}>
          <ValueField
            fieldKey={fieldKey.dose(row.id)}
            testId={`plan-cell-${row.id}-same-d`}
            value={row.dose}
            view={view}
            suffix={unit(view.suffix)}
            ariaLabel={t("aria.rest")}
            onChange={(v) => write((p) => setRowFields(p, row.id, { dose: v }), { typing: true })}
          />
        </span>
      );
    }
    if (k !== "d" && k !== "l" && !has.has(k)) return <span key={k} className={s.xv} data-label={label} data-empty="" />;
    if (per) {
      return (
        <span key={k} className={s.xv} data-label={label}>
          <button type="button" className={s.sumv} data-testid={`plan-sum-${row.id}-${k}`} tabIndex={-1} onClick={() => focusFirst(row.id, k)}>
            {perSummary(row, k, occ.length) || "—"}
          </button>
        </span>
      );
    }
    const view = compactField(row, k);
    const value = k === "d" ? row.dose : k === "l" ? row.load : (row.x?.[k] ?? "");
    const fk = k === "d" ? fieldKey.dose(row.id) : k === "l" ? fieldKey.load(row.id) : fieldKey.x(row.id, k);
    return (
      <span key={k} className={s.xv} data-label={label}>
        <ValueField
          fieldKey={fk}
          testId={`plan-cell-${row.id}-same-${k}`}
          value={value}
          view={view}
          errorText={msg(view.error)}
          suffix={unit(view.suffix)}
          ariaLabel={k === "d" ? t("aria.reps") : k === "l" ? t("aria.load") : labels.column(k)}
          onChange={(v) =>
            write(
              (p) => (k === "d" ? setRowFields(p, row.id, { dose: v }) : k === "l" ? setRowFields(p, row.id, { load: v }) : setRowMeasure(p, row.id, k, v)),
              { typing: true },
            )
          }
        />
      </span>
    );
  });
  return (
    <>
      <div className={s.xr} data-nav-row={row.id} data-grouped={grouped ? "" : undefined} data-per={per ? "" : undefined} data-testid={`plan-row-${row.id}`}>
        <span className={s.xn}>
          <NameCell row={row} />
        </span>
        {cells}
        <span className={s.xm}>
          <MoreButton row={row} />
        </span>
      </div>
      {hasNote(row, notesOpen) ? (
        <div className={s.xnote}>
          <NoteLine row={row} />
        </div>
      ) : null}
      {per ? (
        <div className={s.xp}>
          <ValuesTable row={row} occ={occ} word={word} testId={`plan-rounds-${row.id}`} />
        </div>
      ) : null}
    </>
  );
}

function focusFirst(rowId: string, k: ColKey) {
  document.querySelector<HTMLInputElement>(`[data-key="${attr(fieldKey.cell(rowId, 0, k))}"]`)?.focus();
}

