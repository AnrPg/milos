"use client";

import { useEffect, useMemo, useState, type ReactNode } from "react";
import { useTranslations } from "next-intl";

import type { GoalFeedbackEntryKind, GoalFeedbackResponse, MemberWorkoutGoals } from "@/api/wod-goals";
import { AnatomyFigure } from "@/components/anatomy/AnatomyFigure";
import { useBodySettings } from "@/components/body/use-body";
import { useUiTranslations } from "@/i18n/ui";
import { feltHighlights, goalHighlights, toggleValue } from "@/lib/wod-goals/goals";

import { MuscleChip, RoleLegend, ToggleChip } from "./GoalChips";
import { MusclePickerSheet } from "./MusclePickerSheet";
import { useGoalFeedback, useSaveGoalFeedback } from "./use-wod-goals";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

type Layout = "page" | "inline";

/**
 * «Τι ένιωσες;» (Q4): one optional step after a workout. The goal muscles
 * and qualities are chips the member ticks as felt; «+ Κάτι άλλο» and the
 * body add muscles outside the goals; a workout without goals offers the
 * body alone. `onDone(saved)` follows «Αποθήκευση» or «Παράλειψη».
 */
export function FeltStep({
  entryKind,
  entryId,
  layout = "page",
  onDone,
  onBack,
}: {
  entryKind: GoalFeedbackEntryKind;
  entryId: string;
  layout?: Layout;
  onDone: (saved: boolean) => void;
  onBack?: () => void;
}) {
  const t = useTranslations("WodGoals");
  const feedback = useGoalFeedback(entryKind, entryId);
  const noGoals = feedback.isSuccess && feedback.data.goals === null;
  // Without goals the step follows the member's «Τι ένιωσες; και χωρίς στόχους» setting.
  const bodySettings = useBodySettings(noGoals);
  const optedOut = noGoals && bodySettings.data?.settings.felt_prompt_without_goals === false;
  const skip = feedback.data?.voided === true || optedOut;
  const waiting = feedback.isPending || (noGoals && bodySettings.isPending);

  useEffect(() => {
    if (skip) onDone(false);
  }, [skip, onDone]);

  if (waiting || skip) {
    return (
      <Frame layout={layout} onBack={onBack} onSkip={() => onDone(false)}>
        <p className="py-8 text-center text-sm" style={{ color: "var(--dim)" }}>{t("felt.loading")}</p>
      </Frame>
    );
  }
  // A failed read still offers the body; saving tells if the entry is unreachable.
  return <FeltForm entryKind={entryKind} entryId={entryId} layout={layout} response={feedback.data ?? null} onDone={onDone} onBack={onBack} />;
}

function FeltForm({
  entryKind,
  entryId,
  layout,
  response,
  onDone,
  onBack,
}: {
  entryKind: GoalFeedbackEntryKind;
  entryId: string;
  layout: Layout;
  response: GoalFeedbackResponse | null;
  onDone: (saved: boolean) => void;
  onBack?: () => void;
}) {
  const t = useTranslations("WodGoals");
  const anatomy = useTranslations("Anatomy");
  const goals: MemberWorkoutGoals | null = response?.goals ?? null;
  const [felt, setFelt] = useState<string[]>(response?.feedback?.felt_muscles ?? []);
  const [qualities, setQualities] = useState<string[]>(response?.feedback?.felt_qualities ?? []);
  const [pickerOpen, setPickerOpen] = useState(false);
  const save = useSaveGoalFeedback(entryKind, entryId);
  const goalMuscles = useMemo(() => goals?.muscles ?? [], [goals]);
  const goalIds = goalMuscles.map((muscle) => muscle.id);
  const extras = felt.filter((id) => !goalIds.includes(id));
  const name = (id: string) => anatomy(`muscle.${id}`);
  const backdrop = useMemo(() => goalHighlights(goalMuscles), [goalMuscles]);

  async function submit() {
    try {
      await save.mutateAsync({ felt_muscles: felt, felt_qualities: qualities });
      onDone(true);
    } catch {
      // The error line below offers retry or skip.
    }
  }

  return (
    <Frame
      layout={layout}
      onBack={onBack}
      onSkip={() => onDone(false)}
      footer={
        <>
          {save.isError ? (
            <ErrorNotice>{t("felt.error")}</ErrorNotice>
          ) : null}
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => onDone(false)}
              className="min-h-12 flex-1 rounded-2xl text-sm font-semibold"
              style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
            >
              {t("felt.skip")}
            </button>
            <button
              type="button"
              onClick={() => void submit()}
              disabled={save.isPending}
              className="min-h-12 flex-1 rounded-2xl text-sm font-bold disabled:opacity-50"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {save.isPending ? t("felt.saving") : t("felt.save")}
            </button>
          </div>
        </>
      }
    >
      <p className="text-center text-sm" style={{ color: "var(--muted, var(--text-soft))" }}>
        {goals ? t("felt.subtitle") : t("felt.noGoalsSubtitle")}
      </p>
      <AnatomyFigure
        highlights={feltHighlights(goalMuscles, felt)}
        view="both"
        interactive
        onPick={(nodeId) => setFelt((current) => toggleValue(current, nodeId))}
        size="card"
      />
      <RoleLegend roles={goals ? ["primary", "secondary", "stabilizer", "felt"] : ["felt"]} />

      <section className="flex flex-col gap-2">
        <h3 className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("muscles")}</h3>
        <div className="flex flex-wrap gap-1.5">
          {goalMuscles.map((muscle) => (
            <ToggleChip
              key={muscle.id}
              tone="var(--anatomy-felt)"
              pressed={felt.includes(muscle.id)}
              onToggle={() => setFelt((current) => toggleValue(current, muscle.id))}
            >
              {name(muscle.id)}
            </ToggleChip>
          ))}
          {extras.map((id) => (
            <MuscleChip
              key={id}
              label={name(id)}
              role="felt"
              removeLabel={t("removeMuscle", { muscle: name(id) })}
              onRemove={() => setFelt((current) => current.filter((item) => item !== id))}
            />
          ))}
          <button
            type="button"
            onClick={() => setPickerOpen(true)}
            className="min-h-9 rounded-full px-3 text-xs font-bold"
            style={{ border: "1px dashed var(--border)", color: "var(--primary-strong, var(--primary))" }}
          >
            {t("felt.somethingElse")}
          </button>
        </div>
      </section>

      {goals && goals.qualities.length > 0 ? (
        <section className="flex flex-col gap-2">
          <h3 className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("qualities")}</h3>
          <div className="flex flex-wrap gap-1.5">
            {goals.qualities.map((quality) => (
              <ToggleChip
                key={quality}
                tone="var(--anatomy-felt)"
                pressed={qualities.includes(quality)}
                onToggle={() => setQualities((current) => toggleValue(current, quality))}
              >
                {anatomy(`quality.${quality}`)}
              </ToggleChip>
            ))}
          </div>
        </section>
      ) : null}

      {pickerOpen ? (
        <MusclePickerSheet
          title={t("picker.feltTitle")}
          hint={t("picker.feltHint")}
          entries={felt.map((id) => ({ id, role: "felt" as const }))}
          roleOptions={["felt"]}
          backdrop={backdrop}
          onChange={(entries) => setFelt(entries.map((entry) => entry.id))}
          onClose={() => setPickerOpen(false)}
        />
      ) : null}
    </Frame>
  );
}

function Frame({
  layout,
  onBack,
  onSkip,
  footer,
  children,
}: {
  layout: Layout;
  onBack?: () => void;
  onSkip: () => void;
  footer?: ReactNode;
  children: ReactNode;
}) {
  const t = useTranslations("WodGoals");
  const i18n = useUiTranslations();
  if (layout === "inline") {
    return (
      <div className="flex flex-col gap-4" data-testid="felt-step">
        <h3 className="text-lg font-bold" style={{ color: "var(--text)" }}>{t("felt.title")}</h3>
        {children}
        {footer ? <div className="flex flex-col gap-2">{footer}</div> : null}
      </div>
    );
  }
  return (
    <div className="flex h-dvh flex-col" style={{ background: "var(--bg)", color: "var(--text)" }} data-testid="felt-step">
      <div className="flex items-center justify-between px-5 pt-8 pb-2">
        {onBack ? (
          <button type="button" onClick={onBack} className="text-sm" style={{ color: "var(--dim)" }}>
            {i18n("backc32ae9f")}
          </button>
        ) : <span />}
        <button type="button" onClick={onSkip} className="text-sm font-semibold" style={{ color: "var(--dim)" }}>
          {t("felt.skip")}
        </button>
      </div>
      <h2 className="px-6 pt-4 pb-2 text-center text-xl font-bold">{t("felt.title")}</h2>
      <div className="flex flex-1 flex-col gap-4 overflow-y-auto px-4 pb-4">{children}</div>
      {footer ? <div className="flex flex-col gap-2 p-4 pt-0">{footer}</div> : null}
    </div>
  );
}
