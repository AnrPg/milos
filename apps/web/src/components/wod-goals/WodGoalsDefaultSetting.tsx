"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchAdminSettings, updateAdminSettings, type AdminSettingsPayload } from "@/api/settings";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

const SETTINGS_KEY = ["admin", "settings"] as const;

/** «Στόχοι ορατοί από προεπιλογή» (gym setting): the members toggle's start on workouts without goals. */
export function WodGoalsDefaultSetting({ token }: { token: string }) {
  const t = useTranslations("WodGoals");
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const settings = useQuery({ queryKey: SETTINGS_KEY, queryFn: () => fetchAdminSettings(token) });
  const save = useMutation({
    mutationFn: (visible: boolean) => updateAdminSettings(token, { workouts: { wod_goals_visible_by_default: visible } }),
    onSuccess: (data) => queryClient.setQueryData<AdminSettingsPayload>(SETTINGS_KEY, data),
  });
  if (!settings.data) return null;
  const checked = save.isPending ? Boolean(save.variables) : settings.data.workouts?.wod_goals_visible_by_default === true;

  return (
    <div className="space-y-2">
      <label className="flex min-h-11 items-center justify-between gap-3">
        <span className="flex flex-col">
          <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("settings.visibleByDefault")}</span>
          <span className="text-xs" style={{ color: "var(--dim)" }}>{t("settings.visibleByDefaultHint")}</span>
        </span>
        <input
          type="checkbox"
          role="switch"
          checked={checked}
          disabled={save.isPending}
          onChange={(event) => save.mutate(event.target.checked)}
          className="h-5 w-5 shrink-0"
          style={{ accentColor: "var(--primary)" }}
        />
      </label>
      {save.error ? (
        <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{localizeError(save.error, i18n)}</p>
      ) : null}
    </div>
  );
}
