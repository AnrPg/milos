"use client";

import { useTranslations } from "next-intl";

import { FLOWS } from "@/lib/structured-plan";
import { stepAvailable, usePlanEditorStore, type PlanEditorSection, type PlanWizardStep } from "@/stores/structured-plan";

import { PlanGrid } from "./grid";
import { useKeyText } from "./plan-text";
import { sectionLetter } from "./SectionCard";
import { StepFlow } from "./StepFlow";
import { StepScore, type PlanLevel } from "./StepScore";
import { StepTime } from "./StepTime";

export const STEP_IDS = ["flow", "time", "exercises", "score"] as const;

const Kbd = ({ children }: { children: string }) => (
  <kbd className="rounded border px-1 font-mono text-[0.7rem]" style={{ borderColor: "var(--border-strong)", color: "var(--muted)" }}>
    {children}
  </kbd>
);

/**
 * The one open section: letter, flow, name and the wizard's four steps
 * (Ροή · Χρόνος · Ασκήσεις · Σκορ); steps without content for the flow are
 * disabled and skipped.
 */
export function OpenSection({ section, index, step, levels }: { section: PlanEditorSection; index: number; step: PlanWizardStep; levels?: PlanLevel[] }) {
  const t = useTranslations("PlanEditor");
  const k = useKeyText();
  const renameSection = usePlanEditorStore((s) => s.renameSection);
  const deleteSection = usePlanEditorStore((s) => s.deleteSection);
  const setStep = usePlanEditorStore((s) => s.setStep);
  const nextStep = usePlanEditorStore((s) => s.nextStep);
  const prevStep = usePlanEditorStore((s) => s.prevStep);
  const { plan } = section;
  const fresh = step === 0 && !plan.blocks.flat().length && plan.flow === "sets";

  return (
    <section
      data-testid="plan-open-section"
      data-sec={section.id}
      aria-label={section.name || sectionLetter(index)}
      className="flex min-w-0 flex-col gap-3 rounded-2xl border p-3 sm:p-4"
      style={{ background: "var(--card)", borderColor: "var(--primary)", color: "var(--text)" }}
    >
      <header className="flex flex-wrap items-center gap-x-3 gap-y-2">
        <span className="grid h-6 w-6 shrink-0 place-items-center rounded-md text-xs font-bold" style={{ background: "var(--text)", color: "var(--bg)" }}>
          {sectionLetter(index)}
        </span>
        <b style={{ color: "var(--primary)" }}>{fresh ? t("newSection") : k(FLOWS[plan.flow].labelKey)}</b>
        <input
          data-testid="plan-section-name"
          data-k={`sname:${section.id}`}
          value={section.name}
          placeholder={t("sectionName")}
          aria-label={t("sectionName")}
          onChange={(e) => renameSection(section.id, e.target.value)}
          className="min-w-0 flex-[1_1_8rem] rounded-lg border border-transparent bg-transparent px-1.5 py-1 font-bold outline-none focus:border-[var(--primary)]"
          style={{ color: "var(--text)" }}
        />
        <nav aria-label={t("steps")} className="flex flex-wrap gap-1">
          {STEP_IDS.map((id, n) => {
            const s = n as PlanWizardStep;
            const current = s === step;
            return (
              <button
                key={id}
                type="button"
                data-testid={`plan-step-${id}`}
                aria-current={current ? "step" : undefined}
                disabled={!stepAvailable(plan.flow, s)}
                title={`Alt+${n + 1}`}
                onClick={() => setStep(s)}
                className="rounded-full px-2.5 py-1 text-sm font-semibold disabled:opacity-40"
                style={current ? { background: "var(--selection)", color: "var(--primary)" } : { color: "var(--muted)" }}
              >
                {n + 1} {t(`step.${id}`)}
              </button>
            );
          })}
        </nav>
      </header>

      {step === 0 ? <StepFlow section={section} /> : null}
      {step === 1 ? <StepTime section={section} /> : null}
      {step === 2 ? <PlanGrid section={section} /> : null}
      {step === 3 ? <StepScore section={section} levels={levels} /> : null}

      <footer className="flex flex-wrap items-center justify-between gap-2">
        <span className="flex flex-wrap items-center gap-1.5">
          {step > 0 ? (
            <button type="button" onClick={prevStep} className="rounded-full border px-3 py-1.5 text-sm font-semibold" style={{ borderColor: "var(--border)", color: "var(--text)" }}>
              {t("back")}
            </button>
          ) : null}
          <Kbd>Alt+←</Kbd>
          <Kbd>Alt+→</Kbd>
          {!fresh ? (
            <button
              type="button"
              data-testid="plan-section-delete"
              onClick={() => deleteSection(section.id)}
              className="ms-2 text-xs underline-offset-2 hover:underline"
              style={{ color: "var(--muted)" }}
            >
              {t("deleteSection")}
            </button>
          ) : null}
        </span>
        {step === 0 ? (
          <span className="flex items-center gap-1.5 text-xs" style={{ color: "var(--muted)" }}>
            {t("pickHelp")} <Kbd>↑ ↓</Kbd> <Kbd>Enter</Kbd>
          </span>
        ) : (
          <button
            type="button"
            data-testid="plan-step-next"
            onClick={nextStep}
            className="rounded-full px-4 py-1.5 text-sm font-bold"
            style={{ background: "var(--text)", color: "var(--bg)" }}
          >
            {step === 3 ? t("finish") : t("next")}
          </button>
        )}
      </footer>
    </section>
  );
}
