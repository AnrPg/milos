"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import {
  AI_SETTINGS_KEY,
  fetchAiSettings,
  updateAiSettings,
  type GymAiSettings,
  type GymAiSettingsUpdate,
} from "@/api/scaling";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

const fieldClass = "min-h-11 w-full rounded-xl px-3 text-sm";
const fieldStyle = { background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" };

/**
 * The gym's AI settings (ADR-174): scaling suggestions off by default, the
 * gym's own key (write-only, shown as «•••• last4») and
 * this month's usage. One switch, one key field: no other controls.
 */
// ADR-175: voice logging has its own switch next to scaling, same key.
function VoiceLogSwitch({
  data,
  pending: update,
  busy,
  onChange,
}: {
  data: GymAiSettings;
  pending: GymAiSettingsUpdate | null;
  busy: boolean;
  onChange: (body: GymAiSettingsUpdate) => void;
}) {
  const t = useTranslations("VoiceLog");
  const enabled = data.voice_enabled === true;
  const pending = update?.voice_enabled !== undefined;
  return (
    <label className="flex min-h-11 items-center justify-between gap-3">
      <span className="flex flex-col">
        <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("settings.enable")}</span>
        <span className="text-xs" style={{ color: "var(--dim)" }}>{t("settings.enableHint")}</span>
      </span>
      <input
        type="checkbox"
        role="switch"
        aria-label={t("settings.enable")}
        checked={pending ? Boolean(update?.voice_enabled) : enabled}
        disabled={busy || (!data.key_configured && !enabled)}
        onChange={(event) => onChange({ voice_enabled: event.target.checked })}
        className="h-5 w-5 shrink-0"
        style={{ accentColor: "var(--primary)" }}
      />
    </label>
  );
}

export function AiScalingSettings({ token }: { token: string }) {
  const t = useTranslations("Scaling");
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const [key, setKey] = useState("");
  const settings = useQuery({ queryKey: AI_SETTINGS_KEY, queryFn: () => fetchAiSettings(token) });
  // The update being saved, set in the same event as the tap: the mutation's
  // own pending state reaches React a tick later, and a controlled switch
  // would flip back for that tick.
  const [pendingUpdate, setPendingUpdate] = useState<GymAiSettingsUpdate | null>(null);
  const save = useMutation({
    mutationFn: (body: GymAiSettingsUpdate) => updateAiSettings(token, body),
    onSuccess: (data) => {
      queryClient.setQueryData<GymAiSettings>(AI_SETTINGS_KEY, data);
      setKey("");
    },
    onSettled: () => setPendingUpdate(null),
  });
  const busy = save.isPending || pendingUpdate !== null;
  const submit = (body: GymAiSettingsUpdate) => {
    setPendingUpdate(body);
    save.mutate(body);
  };

  if (settings.isPending) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (!settings.data) {
    return settings.error ? (
      <ErrorNotice>{localizeError(settings.error, i18n)}</ErrorNotice>
    ) : null;
  }

  const data = settings.data;
  const usage = data.usage ?? { suggestions: 0, cost_usd: 0 };
  const enabled = data.scaling_enabled === true;
  const status = data.key_status ?? "unknown";

  return (
    <div className="space-y-5" data-testid="ai-scaling-settings">
      <label className="flex min-h-11 items-center justify-between gap-3">
        <span className="flex flex-col">
          <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("settings.enable")}</span>
          <span className="text-xs" style={{ color: "var(--dim)" }}>{t("settings.enableHint")}</span>
        </span>
        <input
          type="checkbox"
          role="switch"
          aria-label={t("settings.enable")}
          checked={pendingUpdate?.scaling_enabled !== undefined ? Boolean(pendingUpdate.scaling_enabled) : enabled}
          disabled={busy || (!data.key_configured && !enabled)}
          onChange={(event) => submit({ scaling_enabled: event.target.checked })}
          className="h-5 w-5 shrink-0"
          style={{ accentColor: "var(--primary)" }}
        />
      </label>

      <VoiceLogSwitch data={data} pending={pendingUpdate} busy={busy} onChange={submit} />

      <form
        className="space-y-2"
        onSubmit={(event) => {
          event.preventDefault();
          if (key.trim().length >= 20) submit({ api_key: key.trim() });
        }}
      >
        <label className="text-sm font-semibold" htmlFor="ai-api-key" style={{ color: "var(--text)" }}>
          {t("settings.key")}
        </label>
        <p className="text-xs" style={{ color: "var(--dim)" }}>
          {data.key_configured
            ? t(status === "rejected" ? "settings.keyRejected" : "settings.keySet", { last4: data.key_last4 ?? "" })
            : t("settings.keyMissing")}
        </p>
        <div className="flex gap-2">
          <input
            id="ai-api-key"
            type="password"
            autoComplete="off"
            className={fieldClass}
            style={fieldStyle}
            value={key}
            placeholder={data.key_configured ? `•••• ${data.key_last4 ?? ""}` : t("settings.keyPlaceholder")}
            onChange={(event) => setKey(event.target.value)}
          />
          <button
            type="submit"
            className="min-h-11 shrink-0 rounded-xl px-4 text-sm font-bold disabled:opacity-60"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            disabled={key.trim().length < 20 || busy}
          >
            {t("settings.saveKey")}
          </button>
        </div>
        {data.key_configured ? (
          <button
            type="button"
            className="text-xs font-semibold"
            style={{ color: "var(--danger)" }}
            onClick={() => submit({ remove_key: true })}
            disabled={busy}
          >
            {t("settings.removeKey")}
          </button>
        ) : null}
      </form>

      {/* ADR-255: the model is no owner's choice any more ("remove"); the default model is used. */}
      <p className="text-xs" style={{ color: "var(--dim)" }} data-testid="ai-usage">
        {t("settings.usage", { count: usage.suggestions, cost: (usage.cost_usd ?? 0).toFixed(2) })}
      </p>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("settings.privacy")}</p>

      {save.error ? (
        <ErrorNotice>{localizeError(save.error, i18n)}</ErrorNotice>
      ) : null}
    </div>
  );
}
