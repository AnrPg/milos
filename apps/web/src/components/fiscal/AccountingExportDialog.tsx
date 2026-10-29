"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { fetchAccountingExport, fetchExportFormats, saveBlob, saveExportSettings, type ExportFormat, type ExportFormats } from "@/api/fiscal";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { useUiTranslations } from "@/i18n/ui";
import { formErrorsFrom } from "@/lib/form-errors";
import { FRESHNESS } from "@/lib/query-policy";

import { localToday } from "./documents-model";
import { ghostButtonClass, ghostButtonStyle, hintStyle, Icon, primaryButtonStyle } from "./fiscal-ui";
import { PeriodPicker, periodFor, type Period } from "./PeriodPicker";

const FORMATS_KEY = ["admin", "fiscal", "export-formats"] as const;

type Option = ExportFormat["options"][number];
type Values = Record<string, unknown>;

/** A map option as editable text: one "key=value" per line. */
export function mapToText(value: unknown): string {
  if (!value || typeof value !== "object") return "";
  return Object.entries(value as Record<string, unknown>)
    .map(([key, entry]) => `${key}=${entry ?? ""}`)
    .join("\n");
}

export function textToMap(text: string): Record<string, string> {
  const map: Record<string, string> = {};
  for (const line of text.split("\n")) {
    const at = line.indexOf("=");
    if (at <= 0) continue;
    const key = line.slice(0, at).trim();
    if (key) map[key] = line.slice(at + 1).trim();
  }
  return map;
}

/** The options to send: blank fields fall back to the format's defaults. */
export function optionsToSave(options: Option[], values: Values): Values {
  const out: Values = {};
  for (const option of options) {
    const value = values[option.key];
    if (value === undefined || value === "" || value === null) continue;
    if (option.type === "integer") {
      const number = Number(value);
      if (Number.isFinite(number)) out[option.key] = Math.trunc(number);
    } else if (option.type === "map") {
      const map = typeof value === "string" ? textToMap(value) : value;
      if (map && Object.keys(map as object).length > 0) out[option.key] = map;
    } else out[option.key] = value;
  }
  return out;
}

function initialValues(format: ExportFormat, data: ExportFormats): Values {
  const saved = data.settings.find((setting) => setting.format === format.id)?.options ?? {};
  const values: Values = {};
  for (const option of format.options) {
    const value = saved[option.key] ?? option.default;
    values[option.key] = option.type === "map" ? mapToText(value) : value ?? "";
  }
  return values;
}

/** «Εξαγωγή για λογιστή» (ADR-245): a period's documents in the file the accountant's program imports. */
export function AccountingExportDialog({ token, onClose }: { token: string; onClose: () => void }) {
  const t = useTranslations("FiscalDocuments");
  const formats = useQuery({ queryKey: FORMATS_KEY, enabled: Boolean(token), staleTime: FRESHNESS.reference, queryFn: () => fetchExportFormats(token) });

  if (formats.isPending || formats.isError) {
    return (
      <Dialog variant="sheet" size="lg" title={t("exportTitle")} onClose={onClose} testId="fiscal-export-dialog">
        {formats.isError ? <ErrorNotice>{t("formatsFailed")}</ErrorNotice> : <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>}
      </Dialog>
    );
  }
  return <ExportForm token={token} data={formats.data} onClose={onClose} />;
}

function ExportForm({ token, data, onClose }: { token: string; data: ExportFormats; onClose: () => void }) {
  const t = useTranslations("FiscalDocuments");
  const translate = useUiTranslations();
  const queryClient = useQueryClient();
  const today = localToday();
  const [formatId, setFormatId] = useState(() => data.settings.find((setting) => setting.saved)?.format ?? data.formats[0]?.id ?? "");
  const [period, setPeriod] = useState<Period>({ choice: "previousMonth", ...periodFor("previousMonth", today, { from: today, to: today }) });
  const format = data.formats.find((entry) => entry.id === formatId) ?? data.formats[0];
  const [values, setValues] = useState<Values>(() => (format ? initialValues(format, data) : {}));
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  const pickFormat = (id: string) => {
    const next = data.formats.find((entry) => entry.id === id);
    setFormatId(id);
    setValues(next ? initialValues(next, data) : {});
    setError(null);
    setSaved(false);
  };

  const saveSettings = useMutation({
    mutationFn: () => saveExportSettings(token, format!.id, optionsToSave(format!.options, values)),
    onSuccess: () => {
      setSaved(true);
      setError(null);
      void queryClient.invalidateQueries({ queryKey: FORMATS_KEY });
    },
    onError: (failure) => setError(formErrorsFrom(failure, translate, []).message),
  });
  const download = useMutation({
    mutationFn: () => fetchAccountingExport(token, format!.id, period.from, period.to),
    onSuccess: (blob) => saveBlob(blob, `${format!.file_prefix}-${period.from}-${period.to}.${format!.file_extension}`),
    onError: (failure) => setError(formErrorsFrom(failure, translate, []).message),
  });

  return (
    <Dialog
      variant="sheet"
      size="lg"
      title={t("exportTitle")}
      onClose={onClose}
      dismissible={!download.isPending && !saveSettings.isPending}
      error={error}
      testId="fiscal-export-dialog"
      footer={
        <button
          type="button"
          className={ghostButtonClass}
          style={primaryButtonStyle}
          onClick={() => download.mutate()}
          disabled={!format || download.isPending || !period.from || !period.to}
          data-testid="fiscal-export-download"
        >
          <Icon name="download" size={15} />
          {download.isPending ? t("preparing") : t("download")}
        </button>
      }
    >
      <div className="grid gap-3 text-sm" style={{ color: "var(--text)" }}>
        <p className="text-xs" style={hintStyle}>{t("exportHint")}</p>
        <fieldset className="grid gap-1.5">
          <legend className="mb-1.5 text-xs font-bold" style={{ color: "var(--text-soft)" }}>{t("exportFormat")}</legend>
          <div role="radiogroup" aria-label={t("exportFormat")} className="grid gap-1.5">
            {data.formats.map((entry) => {
              const on = entry.id === format?.id;
              return (
                <button
                  key={entry.id}
                  type="button"
                  role="radio"
                  aria-checked={on}
                  onClick={() => pickFormat(entry.id)}
                  data-testid={`fiscal-export-format-${entry.id}`}
                  className="flex items-start gap-2.5 rounded-[14px] p-2.5 text-start"
                  style={{ background: "var(--panel)", border: `1px solid ${on ? "var(--primary)" : "var(--border)"}`, boxShadow: on ? "inset 0 0 0 1px var(--primary)" : undefined }}
                >
                  <span
                    aria-hidden="true"
                    className="mt-0.5 h-4 w-4 flex-none rounded-full"
                    style={{ border: `2px solid ${on ? "var(--primary)" : "var(--border-strong)"}`, background: on ? "var(--primary)" : "transparent", boxShadow: on ? "inset 0 0 0 3px var(--panel)" : undefined }}
                  />
                  <span className="min-w-0 flex-1">
                    <b className="block">{entry.name}</b>
                    <span className="text-xs" style={hintStyle}>{entry.description}</span>
                  </span>
                </button>
              );
            })}
          </div>
        </fieldset>

        <PeriodPicker label={t("period")} today={today} value={period} onChange={setPeriod} testId="fiscal-export-period" />

        {format && format.options.length > 0 ? (
          <details className="rounded-[14px] px-3 py-2" style={{ border: "1px solid var(--border)" }} data-testid="fiscal-export-settings">
            <summary className="cursor-pointer text-sm font-bold">{t("exportSettings", { format: format.name })}</summary>
            <div className="mt-3 grid gap-3">
              <p className="text-xs" style={hintStyle}>{t("exportSettingsHint")}</p>
              {format.options.map((option) => (
                <OptionField
                  key={`${format.id}-${option.key}`}
                  option={option}
                  value={values[option.key]}
                  onChange={(value) => {
                    setValues((current) => ({ ...current, [option.key]: value }));
                    setSaved(false);
                  }}
                />
              ))}
              <div className="flex items-center justify-end gap-3">
                {saved ? <span className="text-xs" role="status" style={{ color: "var(--success)" }}>{t("settingsSaved")}</span> : null}
                <button type="button" className={ghostButtonClass} style={ghostButtonStyle} onClick={() => saveSettings.mutate()} disabled={saveSettings.isPending} data-testid="fiscal-export-save-settings">
                  {saveSettings.isPending ? t("saving") : t("saveSettings")}
                </button>
              </div>
            </div>
          </details>
        ) : null}
      </div>
    </Dialog>
  );
}

function OptionField({ option, value, onChange }: { option: Option; value: unknown; onChange: (value: unknown) => void }) {
  const t = useTranslations("FiscalDocuments");
  const id = `fiscal-export-option-${option.key}`;
  const inputStyle = { background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" };

  if (option.type === "boolean") {
    const on = value === true || value === "true";
    return (
      <button type="button" role="switch" aria-checked={on} data-testid={id} onClick={() => onChange(!on)} className="flex items-center gap-3 text-start">
        <span className="min-w-0 flex-1 text-xs" style={{ color: "var(--text-soft)" }}>{option.description}</span>
        <span
          aria-hidden="true"
          className="relative h-6 w-10 flex-none rounded-full transition-colors"
          style={{ background: on ? "var(--success)" : "var(--control-bg)", border: "1px solid var(--border)" }}
        >
          <span className="absolute top-0.5 h-4.5 w-4.5 rounded-full transition-all" style={{ background: "var(--control-knob)", insetInlineStart: on ? "1.1rem" : "0.15rem", width: "1.1rem", height: "1.1rem" }} />
        </span>
      </button>
    );
  }

  return (
    <label className="grid gap-1" htmlFor={id}>
      <span className="text-xs font-bold" style={{ color: "var(--text-soft)" }}>{option.description}</span>
      {option.type === "enum" ? (
        <Select id={id} data-testid={id} value={String(value ?? "")} onValueChange={onChange} className="min-h-10 w-full rounded-xl px-3 text-sm" style={inputStyle}>
          {(option.values ?? []).map((choice) => (
            <option key={choice} value={choice}>{choice}</option>
          ))}
        </Select>
      ) : option.type === "map" ? (
        <textarea
          id={id}
          data-testid={id}
          rows={3}
          value={String(value ?? "")}
          placeholder={t("mapPlaceholder")}
          onChange={(event) => onChange(event.target.value)}
          className="w-full rounded-xl px-3 py-2 font-mono text-xs"
          style={inputStyle}
        />
      ) : (
        <input
          id={id}
          data-testid={id}
          value={String(value ?? "")}
          inputMode={option.type === "integer" ? "numeric" : undefined}
          onChange={(event) => onChange(event.target.value)}
          className="min-h-10 w-full rounded-xl px-3 text-sm"
          style={inputStyle}
        />
      )}
    </label>
  );
}
