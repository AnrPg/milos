"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { fetchAdminSettings, updateAdminSettings, type AdminSettingsPayload } from "@/api/settings";
import { WOD_ASSISTANT_AVAILABILITY_KEY } from "@/api/workouts";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

const SETTINGS_KEY = ["admin", "settings"] as const;

/**
 * ADR-180: the gym's WOD assistant switch. Off, the assistant is never called
 * and coaches write every workout in text sections, a timer each.
 */
export function WodAssistantSetting({ token }: { token: string }) {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const settings = useQuery({ queryKey: SETTINGS_KEY, queryFn: () => fetchAdminSettings(token) });
  const save = useMutation({
    mutationFn: (enabled: boolean) => updateAdminSettings(token, { workouts: { wod_assistant_enabled: enabled } }),
    onSuccess: (data) => {
      queryClient.setQueryData<AdminSettingsPayload>(SETTINGS_KEY, data);
      void queryClient.invalidateQueries({ queryKey: WOD_ASSISTANT_AVAILABILITY_KEY });
    },
  });
  if (!settings.data) return null;
  const checked = save.isPending ? Boolean(save.variables) : settings.data.workouts?.wod_assistant_enabled !== false;

  return (
    <div className="space-y-2" data-testid="wod-assistant-setting">
      <label className="flex min-h-11 items-center justify-between gap-3">
        <span className="flex flex-col">
          <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{i18n("wodAssistantSettingLabel")}</span>
          <span className="text-xs" style={{ color: "var(--dim)" }}>{i18n("wodAssistantSettingHint")}</span>
        </span>
        <input
          type="checkbox"
          role="switch"
          aria-label={i18n("wodAssistantSettingLabel")}
          checked={checked}
          disabled={save.isPending}
          onChange={(event) => save.mutate(event.target.checked)}
          className="h-5 w-5 shrink-0"
          style={{ accentColor: "var(--primary)" }}
        />
      </label>
      {save.error ? (
        <ErrorNotice>{localizeError(save.error, i18n)}</ErrorNotice>
      ) : null}
    </div>
  );
}
