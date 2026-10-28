"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { useTranslations } from "next-intl";

import { fetchClientTrainingGoal, saveClientTrainingGoal } from "@/api/staff";
import { useSession } from "@/components/session-provider";
import { primaryButtonClass, primaryButtonStyle, StatusText } from "@/components/staff/staff-ui";
import { GoalStepper } from "@/components/training-goal/GoalStepper";
import { goalBounds, goalSetterNote, weeklyTarget } from "@/components/training-goal/training-goal";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

/**
 * A client's weekly goal on their profile (ADR-221), for their coach or an
 * owner/admin who may coach every client. Saving tells the client, who can
 * change it back.
 */
export function ClientTrainingGoalPanel({ userId, nickname }: { userId: string; nickname: string }) {
  const t = useTranslations("TrainingGoal");
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const queryClient = useQueryClient();
  const key = ["staff", "clients", userId, "training-goal"];
  const [draft, setDraft] = useState<number | null>(null);

  const goal = useQuery({
    queryKey: key,
    enabled: Boolean(token),
    queryFn: () => fetchClientTrainingGoal(token!, userId),
  });
  const save = useMutation({
    mutationFn: (target: number) => saveClientTrainingGoal(token!, userId, target),
    onSuccess: (saved) => {
      queryClient.setQueryData(key, saved);
      setDraft(null);
    },
  });

  if (goal.isError) return <StatusText tone="error">{localizeError(goal.error, i18n)}</StatusText>;

  const current = weeklyTarget(goal.data);
  const value = draft ?? current;
  const { min, max } = goalBounds(goal.data);
  const note = goalSetterNote(goal.data);

  return (
    <div className="space-y-3" data-testid="client-training-goal">
      <p className="text-sm leading-6" style={{ color: "var(--muted)" }}>
        {t("staffHint", { name: nickname })}
      </p>
      <GoalStepper value={value} min={min} max={max} disabled={goal.isPending || save.isPending} onChange={setDraft} />
      <p className="text-xs" style={{ color: "var(--dim)" }}>
        {note.kind === "default"
          ? t("staffDefault", { count: current })
          : note.kind === "self"
            ? t("staffSetBySelf", { name: nickname })
            : t("staffSetBy", { name: note.name })}
      </p>
      <div className="flex items-center gap-3">
        <button
          type="button"
          className={primaryButtonClass}
          style={primaryButtonStyle}
          disabled={draft === null || draft === current || save.isPending}
          onClick={() => draft !== null && save.mutate(draft)}
        >
          {t("staffSave")}
        </button>
        {save.isSuccess && draft === null ? <StatusText tone="success">{t("staffSaved", { name: nickname })}</StatusText> : null}
        {save.isError ? <StatusText tone="error">{localizeError(save.error, i18n)}</StatusText> : null}
      </div>
    </div>
  );
}
