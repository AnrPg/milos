"use client";

import { useTranslations } from "next-intl";

import type { BodySettingsUpdate, BodyUnits, BodyVisibility, WeightDisplay } from "@/api/body";
import { LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { ChoicePill, ErrorLine } from "@/components/community/Sheet";
import { key } from "@/components/body/BodyBits";
import { bodyErrorMessage } from "@/components/body/errors";
import { useBodySettings, useUpdateBodySettings } from "@/components/body/use-body";
import { useUiTranslations } from "@/i18n/ui";

const SECTIONS = ["body", "wellness", "cravings"] as const;

export function Switch({
  checked,
  onChange,
  label,
  hint,
  disabled,
}: {
  checked: boolean;
  onChange: (next: boolean) => void;
  label: string;
  hint?: string;
  disabled?: boolean;
}) {
  return (
    <label className="flex min-h-11 items-center justify-between gap-3">
      <span className="flex flex-col">
        <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{label}</span>
        {hint ? <span className="text-xs" style={{ color: "var(--dim)" }}>{hint}</span> : null}
      </span>
      <input
        type="checkbox"
        role="switch"
        checked={checked}
        disabled={disabled}
        onChange={(event) => onChange(event.target.checked)}
        className="h-5 w-5 shrink-0"
        style={{ accentColor: "var(--primary)" }}
      />
    </label>
  );
}

/** The member's body settings and a save that reports its own error. */
function useBodyPrefs() {
  const settings = useBodySettings();
  const update = useUpdateBodySettings();
  return { settings, update, save: (change: BodySettingsUpdate) => update.mutate(change) };
}

function Pending({ settings }: { settings: ReturnType<typeof useBodySettings> }) {
  if (settings.isPending) return <LoadingLine />;
  if (settings.isError) return <QueryProblem error={settings.error} onRetry={() => void settings.refetch()} />;
  return null;
}

function SaveError({ error }: { error: unknown }) {
  const t = useTranslations("Body");
  const tUi = useUiTranslations();
  return <ErrorLine message={error ? bodyErrorMessage(error, t, tUi) : null} />;
}

/** Ρυθμίσεις › Μονάδες (vision §7.11, ADR-196): metric or imperial, everywhere measurements show. */
export function UnitsSetting() {
  const t = useTranslations("Body");
  const { settings, update, save } = useBodyPrefs();
  const prefs = settings.data?.settings;
  if (!prefs) return <Pending settings={settings} />;
  return (
    <div className="flex flex-col gap-3">
      <div role="radiogroup" aria-label={t("unitsLabel")} className="flex gap-2">
        {(["metric", "imperial"] as BodyUnits[]).map((item) => (
          <ChoicePill key={item} selected={prefs.units === item} onSelect={() => save({ units: item })}>
            {t(key("units", item))}
          </ChoicePill>
        ))}
      </div>
      <SaveError error={update.error} />
    </div>
  );
}

/**
 * Ρυθμίσεις › Ενότητες ημερολογίου (vision §7.11, ADR-158 §7, ADR-196):
 * which journal sections exist, whether the weight shows as a number or a
 * trend, and the «πώς το ένιωσες» prompt.
 */
export function JournalSectionsSetting() {
  const t = useTranslations("Body");
  const goalsT = useTranslations("WodGoals");
  const { settings, update, save } = useBodyPrefs();
  const prefs = settings.data?.settings;
  if (!prefs) return <Pending settings={settings} />;
  return (
    <div className="flex flex-col gap-3">
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("sectionsHint")}</p>
      {SECTIONS.map((section) => (
        <Switch
          key={section}
          label={t(key("section", section))}
          checked={prefs.journal_sections[section] !== false}
          onChange={(next) => save({ journal_sections: { [section]: next } })}
        />
      ))}
      <Switch
        label={goalsT("settings.feltPrompt")}
        hint={goalsT("settings.feltPromptHint")}
        checked={prefs.felt_prompt_without_goals !== false}
        onChange={(next) => save({ felt_prompt_without_goals: next })}
      />
      <div className="flex flex-col gap-2 border-t pt-3" style={{ borderColor: "var(--border)" }}>
        <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("weightDisplayQuestion")}</p>
        <div role="radiogroup" aria-label={t("weightDisplayQuestion")} className="flex flex-col gap-2">
          {(["number", "trend", "hidden"] as WeightDisplay[]).map((item) => (
            <ChoicePill key={item} selected={prefs.weight_display === item} onSelect={() => save({ weight_display: item })} hint={t(key("weightDisplayHint", item))}>
              {t(key("weightDisplay", item))}
            </ChoicePill>
          ))}
        </div>
      </div>
      <SaveError error={update.error} />
    </div>
  );
}

/**
 * Κοινοποίηση › Προεπιλογή νέων καταχωρήσεων › Μετρήσεις (ADR-158, ADR-196):
 * who sees a new measurement. Photos never reach a coach without consent.
 */
export function BodyDefaultVisibilitySetting() {
  const t = useTranslations("Body");
  const { settings, update, save } = useBodyPrefs();
  const prefs = settings.data?.settings;
  if (!prefs) return <Pending settings={settings} />;
  return (
    <div className="flex flex-col gap-2">
      <div role="radiogroup" aria-label={t("defaultVisibilityLabel")} className="flex flex-col gap-2">
        {(["private", "coach_numbers", "coach_full"] as BodyVisibility[]).map((item) => (
          <ChoicePill key={item} selected={prefs.default_visibility === item} onSelect={() => save({ default_visibility: item })} hint={t(key("visibilityHint", item))}>
            {t(key("visibility", item))}
          </ChoicePill>
        ))}
      </div>
      <SaveError error={update.error} />
    </div>
  );
}
