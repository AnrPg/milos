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

const fieldClass = "min-h-11 w-full rounded-xl px-3 text-sm";
const fieldStyle = { background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" };

/**
 * The gym's AI settings (ADR-174): scaling suggestions off by default, the
 * gym's own key (write-only, shown as «•••• last4»), an optional model and
 * this month's usage. One switch, one key field: no other controls.
 */
// ADR-175: voice logging has its own switch next to scaling, same key.
function VoiceLogSwitch({
  data,
  save,
}: {
  data: GymAiSettings;
  save: { isPending: boolean; variables?: GymAiSettingsUpdate; mutate: (body: GymAiSettingsUpdate) => void };
}) {
  const t = useTranslations("VoiceLog");
  const enabled = data.voice_enabled === true;
  const pending = save.isPending && save.variables?.voice_enabled !== undefined;
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
        checked={pending ? Boolean(save.variables?.voice_enabled) : enabled}
        disabled={save.isPending || (!data.key_configured && !enabled)}
        onChange={(event) => save.mutate({ voice_enabled: event.target.checked })}
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
  const [model, setModel] = useState<string | null>(null);
  const settings = useQuery({ queryKey: AI_SETTINGS_KEY, queryFn: () => fetchAiSettings(token) });
  const save = useMutation({
    mutationFn: (body: GymAiSettingsUpdate) => updateAiSettings(token, body),
    onSuccess: (data) => {
      queryClient.setQueryData<GymAiSettings>(AI_SETTINGS_KEY, data);
      setKey("");
      setModel(null);
    },
  });

  if (settings.isPending) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (!settings.data) {
    return settings.error ? (
      <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{localizeError(settings.error, i18n)}</p>
    ) : null;
  }

  const data = settings.data;
  const usage = data.usage ?? { suggestions: 0, cost_usd: 0 };
  const enabled = data.scaling_enabled === true;
  const status = data.key_status ?? "unknown";
  const modelValue = model ?? data.model ?? "";

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
          checked={save.isPending && save.variables?.scaling_enabled !== undefined ? Boolean(save.variables.scaling_enabled) : enabled}
          disabled={save.isPending || (!data.key_configured && !enabled)}
          onChange={(event) => save.mutate({ scaling_enabled: event.target.checked })}
          className="h-5 w-5 shrink-0"
          style={{ accentColor: "var(--primary)" }}
        />
      </label>

      <VoiceLogSwitch data={data} save={save} />

      <form
        className="space-y-2"
        onSubmit={(event) => {
          event.preventDefault();
          if (key.trim().length >= 20) save.mutate({ api_key: key.trim() });
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
            style={{ background: "var(--primary)", color: "var(--bg)" }}
            disabled={key.trim().length < 20 || save.isPending}
          >
            {t("settings.saveKey")}
          </button>
        </div>
        {data.key_configured ? (
          <button
            type="button"
            className="text-xs font-semibold"
            style={{ color: "var(--danger)" }}
            onClick={() => save.mutate({ remove_key: true })}
            disabled={save.isPending}
          >
            {t("settings.removeKey")}
          </button>
        ) : null}
      </form>

      <form
        className="space-y-2"
        onSubmit={(event) => {
          event.preventDefault();
          save.mutate({ model: modelValue.trim() === "" ? null : modelValue.trim() });
        }}
      >
        <label className="text-sm font-semibold" htmlFor="ai-model" style={{ color: "var(--text)" }}>
          {t("settings.model")}
        </label>
        <div className="flex gap-2">
          <input
            id="ai-model"
            className={fieldClass}
            style={fieldStyle}
            value={modelValue}
            placeholder={data.default_model}
            onChange={(event) => setModel(event.target.value)}
          />
          <button
            type="submit"
            className="min-h-11 shrink-0 rounded-xl px-4 text-sm font-semibold disabled:opacity-60"
            style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
            disabled={model === null || save.isPending}
          >
            {t("settings.saveModel")}
          </button>
        </div>
      </form>

      <p className="text-xs" style={{ color: "var(--dim)" }} data-testid="ai-usage">
        {t("settings.usage", { count: usage.suggestions, cost: (usage.cost_usd ?? 0).toFixed(2) })}
      </p>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("settings.privacy")}</p>

      {save.error ? (
        <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{localizeError(save.error, i18n)}</p>
      ) : null}
    </div>
  );
}
