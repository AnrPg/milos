"use client";

import type { PlanRow, PlanStructure, PlanUnit } from "@/lib/structured-plan/types";

import { useGridActions } from "./actions";
import { useGrid, useGridT } from "./context";
import { structOf, unitKey } from "./lib";
import { fieldKey, restSuffix } from "./model";
import { setRowFields, setStructField } from "./mutations";
import { ValueField } from "./ValueField";
import s from "./grid.module.css";

/** ⋯: every row action in one place (Alt+M). */
export function MoreButton({ row }: { row: PlanRow }) {
  const { t } = useGridT();
  const act = useGridActions();
  return (
    <button
      type="button"
      className={s.more}
      data-more={row.id}
      data-testid={`plan-row-more-${row.id}`}
      title={t("menu.title")}
      aria-label={t("menu.button")}
      aria-haspopup="dialog"
      onClick={(event) => act.open(row.id, "menu", event.currentTarget, null)}
    >
      ⋯
    </button>
  );
}

/** The quiet note line under a row, once it has a note or Alt+N opened it. */
export function NoteLine({ row }: { row: PlanRow }) {
  const { write, notesOpen } = useGrid();
  const { t } = useGridT();
  if (row.kind !== "ex" || (!row.note && !notesOpen.has(row.id))) return null;
  return (
    <input
      className={s.note}
      data-key={fieldKey.note(row.id)}
      data-testid={`plan-note-${row.id}`}
      value={row.note ?? ""}
      placeholder={t("note.placeholder")}
      aria-label={t("note.placeholder")}
      autoComplete="off"
      onChange={(event) => {
        const note = event.target.value;
        write((plan) => setRowFields(plan, row.id, { note }), { typing: true });
      }}
    />
  );
}

export const hasNote = (row: PlanRow, open: ReadonlySet<string>) => row.kind === "ex" && Boolean(row.note || open.has(row.id));

type FieldDef = { key: string; time: boolean };
const STRUCT_FIELDS: Partial<Record<PlanStructure["kind"], FieldDef[]>> = {
  cluster: [
    { key: "clusters", time: false },
    { key: "intra", time: true },
  ],
  drop: [
    { key: "drops", time: false },
    { key: "dropby", time: false },
  ],
  restpause: [
    { key: "minis", time: false },
    { key: "intra", time: true },
  ],
};

/** The group / structure header: shown only when a unit is more than one plain exercise. */
export function StructHead({ unit }: { unit: PlanUnit }) {
  const { plan, write } = useGrid();
  const { t, core, unit: unitWord } = useGridT();
  const act = useGridActions();
  const st = structOf(plan, unit);
  if (unit.rows.length === 1 && st.kind === "single") return null;
  const key = unitKey(unit);
  const first = unit.rows[0]!;
  const values = st as unknown as Record<string, string>;
  return (
    <div className={s.uhead} data-testid={`plan-struct-${key}`}>
      <button
        type="button"
        className={s.schip}
        title={t("structChip")}
        data-key={`st:${key}`}
        onClick={(event) => act.open(first.id, "struct", event.currentTarget, fieldKey.name(first.id))}
      >
        {core(`struct.${st.kind}`)}
        <span aria-hidden="true"> ▾</span>
      </button>
      {(STRUCT_FIELDS[st.kind] ?? []).map((f) => {
        const value = values[f.key] ?? "";
        const label = core(`structParam.${f.key}`);
        const suffix = f.time ? unitWord(restSuffix(value)) : "";
        return (
          <span key={f.key} className={s.sf}>
            {f.time ? <span>{label}</span> : null}
            <ValueField
              fieldKey={fieldKey.struct(key, f.key)}
              value={value}
              view={{ placeholder: "", display: "", badge: "", error: null, suffix: "" }}
              suffix={suffix}
              ariaLabel={label}
              onChange={(v) => write((p) => setStructField(p, key, f.key, v), { typing: true })}
            />
            {f.time ? null : <span>{label}</span>}
          </span>
        );
      })}
      <span className={s.uhint}>{core(`structHint.${st.kind}`)}</span>
    </div>
  );
}
