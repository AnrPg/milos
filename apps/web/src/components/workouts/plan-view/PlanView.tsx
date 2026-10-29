"use client";

import { useTranslations } from "next-intl";
import { useMemo } from "react";

import type { PlanSection } from "@/lib/structured-plan/types";

import { buildPlanView, type PlanViewRow, type PlanViewSection, type PlanViewUnit } from "./plan-model";

export type PlanViewSource = { id?: string | null; name?: string | null; plan: PlanSection };

type Props = {
  sections: PlanViewSource[];
  /** Labels of the workout's scale levels by key («rx» → «RX»), for per-level notes. */
  levelLabels?: Record<string, string>;
};

/**
 * ADR-270: a structured workout, read-only (staff preview and member screens).
 * Calm and compact: per section the flow and its parameters, then the
 * exercises with their per-set values in WOD notation.
 */
export function PlanView({ sections, levelLabels }: Props) {
  const t = useTranslations("PlanView");
  const views = useMemo(
    () => sections.map((section) => buildPlanView(section.plan, (key, values) => t(key, values), levelLabels)),
    [levelLabels, sections, t],
  );

  if (sections.length === 0) {
    return (
      <p className="text-sm" style={{ color: "var(--muted)" }} data-testid="plan-view">
        {t("empty")}
      </p>
    );
  }

  return (
    <ol className="space-y-3" aria-label={t("label")} data-testid="plan-view">
      {views.map((view, index) => (
        <PlanSectionCard
          key={sections[index]!.id ?? index}
          name={sections[index]!.name?.trim() || t("untitledSection", { letter: String.fromCharCode(65 + index) })}
          view={view}
        />
      ))}
    </ol>
  );
}

function PlanSectionCard({ name, view }: { name: string; view: PlanViewSection }) {
  const t = useTranslations("PlanView");
  return (
    <li className="min-w-0 rounded-[1.2rem] border p-4" style={{ background: "var(--panel)", borderColor: "var(--border)" }} data-testid="plan-view-section">
      <header className="flex min-w-0 flex-wrap items-baseline gap-x-2 gap-y-1">
        <h3 className="min-w-0 break-words text-sm font-bold" style={{ color: "var(--text)" }}>
          {name}
        </h3>
        <span className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--primary)" }} data-testid="plan-view-flow">
          {view.flow}
        </span>
        {view.preset ? (
          <span className="rounded-md px-1.5 py-0.5 text-[11px] font-semibold" style={{ background: "var(--card)", color: "var(--muted)" }}>
            {view.preset}
          </span>
        ) : null}
      </header>
      {view.params ? (
        <p className="mt-0.5 text-xs tabular-nums" style={{ color: "var(--muted)" }} data-testid="plan-view-params">
          {view.params}
        </p>
      ) : null}

      {view.blocks.length > 0 ? (
        <div className="mt-3 space-y-3">
          {view.blocks.map((block) => (
            <section key={block.key} className="min-w-0" aria-label={block.label ?? undefined}>
              {block.label ? (
                <h4 className="mb-1 text-xs font-bold" style={{ color: "var(--text-soft)" }} data-testid="plan-view-block-label">
                  {block.label}
                </h4>
              ) : null}
              <UnitList units={block.units} />
            </section>
          ))}
        </div>
      ) : null}

      {view.interrupt ? (
        <section
          className="mt-3 min-w-0 rounded-xl border-s-2 ps-3"
          style={{ borderColor: "var(--heat)" }}
          aria-label={view.interrupt.label}
          data-testid="plan-view-interrupt"
        >
          <h4 className="mb-1 text-xs font-bold" style={{ color: "var(--text-soft)" }}>
            {view.interrupt.label}
          </h4>
          <UnitList units={view.interrupt.units} />
        </section>
      ) : null}

      {view.score || view.note || view.levelNotes.length > 0 ? (
        <div className="mt-3 space-y-1 text-xs" style={{ color: "var(--muted)" }}>
          {view.score ? <p className="font-semibold">{view.score}</p> : null}
          {view.note ? (
            <p className="whitespace-pre-wrap" aria-label={t("sectionNote")}>
              {view.note}
            </p>
          ) : null}
          {view.levelNotes.length > 0 ? (
            <dl className="space-y-0.5" aria-label={t("levelNotes")}>
              {view.levelNotes.map((level) => (
                <div key={level.level} className="flex min-w-0 gap-1.5">
                  <dt className="shrink-0 font-bold" style={{ color: "var(--text-soft)" }}>
                    {level.label}
                  </dt>
                  <dd className="min-w-0 whitespace-pre-wrap">{level.note}</dd>
                </div>
              ))}
            </dl>
          ) : null}
        </div>
      ) : null}
    </li>
  );
}

function UnitList({ units }: { units: PlanViewUnit[] }) {
  return (
    <ul className="space-y-1.5">
      {units.map((unit) =>
        unit.structure ? (
          <li key={unit.key} className="min-w-0 border-s-2 ps-3" style={{ borderColor: "var(--border-strong)" }}>
            <p className="text-[11px] font-bold uppercase tracking-[0.12em]" style={{ color: "var(--dim)" }} data-testid="plan-view-structure">
              {unit.structure}
            </p>
            <ul className="space-y-1.5">
              {unit.rows.map((row) => (
                <RowItem key={row.id} row={row} />
              ))}
            </ul>
          </li>
        ) : (
          unit.rows.map((row) => <RowItem key={row.id} row={row} />)
        ),
      )}
    </ul>
  );
}

function RowItem({ row }: { row: PlanViewRow }) {
  const t = useTranslations("PlanView");
  const values = [row.dose, row.load ? `@ ${row.load}` : ""].filter(Boolean).join(" ");
  if (row.kind === "rest") {
    return (
      <li className="text-xs" style={{ color: "var(--muted)" }} data-testid="plan-view-row">
        {row.name}
        {row.dose ? <span className="tabular-nums"> {row.dose}</span> : null}
      </li>
    );
  }
  return (
    <li className="min-w-0 text-sm leading-6" data-testid="plan-view-row">
      <div className="flex min-w-0 flex-wrap items-baseline gap-x-2">
        <span className="min-w-0 break-words font-semibold" style={{ color: "var(--text)" }}>
          {row.name}
        </span>
        {row.perSide ? (
          <span className="rounded-md px-1.5 text-[11px] font-semibold" style={{ background: "var(--card)", color: "var(--muted)" }}>
            {t("perSide")}
          </span>
        ) : null}
        {values ? (
          <span className="tabular-nums" style={{ color: "var(--text-soft)" }} data-testid="plan-view-values">
            {values}
          </span>
        ) : null}
      </div>
      {row.measures.length > 0 ? (
        <p className="text-xs tabular-nums" style={{ color: "var(--muted)" }}>
          {row.measures.join(" · ")}
        </p>
      ) : null}
      {row.note ? (
        <p className="whitespace-pre-wrap text-xs" style={{ color: "var(--muted)" }}>
          {row.note}
        </p>
      ) : null}
    </li>
  );
}
