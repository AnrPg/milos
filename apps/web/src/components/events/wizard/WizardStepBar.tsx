"use client";

import { useTranslations } from "next-intl";

import type { EventWizardStep } from "@/lib/event-wizard";

/**
 * The wizard's progress: one segment per step on the full width (never a
 * scrolling row), done ones filled, the current one marked. A visited step
 * is a button that goes back to it; the others are not reachable yet.
 * Phones show «Step 2 of 6 · Basics» under it; wider screens each label.
 */
export function WizardStepBar({
  steps,
  current,
  visited,
  label,
  canVisit,
  onVisit,
}: {
  steps: EventWizardStep[];
  current: EventWizardStep;
  visited: EventWizardStep[];
  label: (step: EventWizardStep) => string;
  canVisit: (step: EventWizardStep) => boolean;
  onVisit: (step: EventWizardStep) => void;
}) {
  const tw = useTranslations("EventWizard");
  const index = steps.indexOf(current);

  return (
    <nav aria-label={tw("stepsLabel")} className="flex flex-col gap-1">
      <ol className="grid gap-1" style={{ gridTemplateColumns: `repeat(${steps.length}, minmax(0, 1fr))` }}>
        {steps.map((step, position) => {
          const isCurrent = step === current;
          const done = visited.includes(step) && !isCurrent;
          const reachable = !isCurrent && canVisit(step);
          const fill = isCurrent ? "var(--primary)" : done ? "color-mix(in srgb, var(--primary) 45%, var(--border))" : "var(--border)";
          const text = tw("stepAria", { current: position + 1, total: steps.length, step: label(step) });
          const content = (
            <>
              <span aria-hidden="true" className="block h-1.5 w-full rounded-full" style={{ background: fill }} />
              <span
                aria-hidden="true"
                className="hidden w-full truncate text-start text-[11px] font-semibold sm:block"
                style={{ color: isCurrent ? "var(--text)" : "var(--dim)" }}
              >
                {label(step)}
              </span>
              <span className="sr-only">{text}</span>
            </>
          );
          return (
            <li key={step} className="min-w-0">
              {reachable ? (
                <button
                  type="button"
                  onClick={() => onVisit(step)}
                  className="flex min-h-11 w-full flex-col justify-center gap-1 rounded-lg"
                >
                  {content}
                </button>
              ) : (
                <span aria-current={isCurrent ? "step" : undefined} className="flex min-h-11 w-full flex-col justify-center gap-1">
                  {content}
                </span>
              )}
            </li>
          );
        })}
      </ol>
      <p className="text-xs font-semibold sm:hidden" style={{ color: "var(--dim)" }} aria-hidden="true">
        {tw("stepOf", { current: index + 1, total: steps.length, step: label(current) })}
      </p>
    </nav>
  );
}
