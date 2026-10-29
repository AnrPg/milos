"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchAdminSettings, updateAdminSettings, type AdminSettingsPayload } from "@/api/settings";
import { WOD_ASSISTANT_AVAILABILITY_KEY } from "@/api/workouts";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useWorkoutTypeLabels } from "@/components/workouts/WorkoutTypeSelect";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { WORKOUT_TYPE_FAMILIES, WORKOUT_TYPES, type WorkoutType } from "@/lib/workout-types";

const SETTINGS_KEY = ["admin", "settings"] as const;

/**
 * ADR-275: which workout kinds the gym's editors offer. Every kind is on
 * until the gym turns some off; at least one stays on. A workout keeps its
 * kind when the gym later hides it.
 */
export function WorkoutTypesSetting({ token }: { token: string }) {
  const t = useTranslations("WorkoutTypes");
  const i18n = useUiTranslations();
  const labels = useWorkoutTypeLabels();
  const queryClient = useQueryClient();
  const settings = useQuery({ queryKey: SETTINGS_KEY, queryFn: () => fetchAdminSettings(token) });
  const save = useMutation({
    mutationFn: (types: WorkoutType[] | null) => updateAdminSettings(token, { workouts: { workout_types: types } }),
    onSuccess: (data) => {
      queryClient.setQueryData<AdminSettingsPayload>(SETTINGS_KEY, data);
      void queryClient.invalidateQueries({ queryKey: WOD_ASSISTANT_AVAILABILITY_KEY });
    },
  });
  if (!settings.data) return null;

  const stored = save.isPending ? save.variables : settings.data.workouts?.workout_types;
  const offered = new Set<string>(stored && stored.length > 0 ? stored : WORKOUT_TYPES);

  function toggle(type: WorkoutType) {
    const next = new Set(offered);
    if (next.has(type)) next.delete(type);
    else next.add(type);
    if (next.size === 0) return;
    const chosen = WORKOUT_TYPES.filter((item) => next.has(item));
    // Every kind on is stored as "no choice", so kinds added later show up too.
    save.mutate(chosen.length === WORKOUT_TYPES.length ? null : chosen);
  }

  return (
    <div className="space-y-4" data-testid="workout-types-setting">
      <p className="text-xs" style={{ color: "var(--dim)" }}>
        {t("setting.hint")}
      </p>
      {WORKOUT_TYPE_FAMILIES.map((group) => (
        <fieldset key={group.family} className="space-y-2">
          <legend className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--muted)" }}>
            {labels.family(group.family)}
          </legend>
          <div className="flex flex-wrap gap-2">
            {group.types.map((type) => {
              const on = offered.has(type);
              return (
                <button
                  key={type}
                  type="button"
                  aria-pressed={on}
                  disabled={save.isPending || (on && offered.size === 1)}
                  onClick={() => toggle(type)}
                  className="min-h-9 rounded-full border px-3 text-sm font-semibold disabled:opacity-60"
                  style={{
                    borderColor: on ? "var(--primary)" : "var(--border)",
                    background: on ? "color-mix(in srgb, var(--primary) 12%, var(--card))" : "var(--card)",
                    color: on ? "var(--text)" : "var(--muted)",
                  }}
                >
                  {labels.type(type)}
                </button>
              );
            })}
          </div>
        </fieldset>
      ))}
      {save.error ? <ErrorNotice>{localizeError(save.error, i18n)}</ErrorNotice> : null}
    </div>
  );
}
