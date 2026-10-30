"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchClientTrainingGoal, saveClientTrainingGoal } from "@/api/staff";
import { useSession } from "@/components/session-provider";
import { StatusText } from "@/components/staff/staff-ui";
import { ChangedMark } from "@/components/ui/ChangedMark";
import { useDraftForm } from "@/components/ui/DraftForms";
import { GoalStepper } from "@/components/training-goal/GoalStepper";
import { goalBounds, goalSetterNote, weeklyTarget } from "@/components/training-goal/training-goal";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

/**
 * A client's weekly goal on their profile (ADR-229), for their coach or an
 * owner/admin who may coach every client. Saving tells the client, who can
 * change it back. ADR-276: the stepper is a draft saved with the profile's
 * «Αποθήκευση» bar.
 */
export function ClientTrainingGoalPanel({ userId, nickname }: { userId: string; nickname: string }) {
  const t = useTranslations("TrainingGoal");
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const queryClient = useQueryClient();
  const key = ["staff", "clients", userId, "training-goal"];
  const goal = useQuery({
    queryKey: key,
    enabled: Boolean(token),
    queryFn: () => fetchClientTrainingGoal(token!, userId),
  });
  const current = weeklyTarget(goal.data);
  const form = useDraftForm<{ target: number }>({
    server: { target: current },
    testId: "training-goal-save-bar",
    save: async (draft) => {
      const saved = await saveClientTrainingGoal(token!, userId, draft.target);
      queryClient.setQueryData(key, saved);
    },
    describeError: (error) => localizeError(error, i18n),
  });

  if (goal.isError) return <StatusText tone="error">{localizeError(goal.error, i18n)}</StatusText>;

  const { min, max } = goalBounds(goal.data);
  const note = goalSetterNote(goal.data);

  return (
    <div className="space-y-3" data-testid="client-training-goal">
      <p className="text-sm leading-6" style={{ color: "var(--muted)" }}>
        {t("staffHint", { name: nickname })}
      </p>
      {form.changed.has("target") ? <ChangedMark /> : null}
      <GoalStepper value={form.draft.target} min={min} max={max} disabled={goal.isPending || form.saving} onChange={(target) => form.edit({ target })} />
      <p className="text-xs" style={{ color: "var(--dim)" }}>
        {note.kind === "default"
          ? t("staffDefault", { count: current })
          : note.kind === "self"
            ? t("staffSetBySelf", { name: nickname })
            : t("staffSetBy", { name: note.name })}
      </p>
      {form.justSaved ? <StatusText tone="success">{t("staffSaved", { name: nickname })}</StatusText> : null}
      {form.bar}
    </div>
  );
}
