"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";

import { saveDocumentSettings, type DocumentSettings } from "@/api/documents";
import { Toggle } from "@/components/admin/finance/packages/package-ui";
import { inputClass, inputStyle, primaryButtonClass, primaryButtonStyle } from "@/components/staff/staff-ui";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";

import { documentError } from "../document-errors";
import { useToken } from "../use-documents";
import { Hint, SettingRow } from "./staff-parts";

/**
 * The box's document rules (ADR-252 §6): whether a missing mandatory
 * document blocks booking (on by default), and how long a health
 * certificate is valid and when clients are reminded. Whether the box asks
 * for the certificate, and whether it blocks booking, live in its panel.
 */
export function SettingsDialog({ settings, onClose, onSaved }: { settings: DocumentSettings; onClose: () => void; onSaved: () => void }) {
  const t = useTranslations("Documents");
  const i18n = useUiTranslations();
  const token = useToken();
  const [block, setBlock] = useState(settings.block_booking_on_unsigned);
  const [months, setMonths] = useState(String(settings.health_certificate_validity_months));
  const [days, setDays] = useState(String(settings.health_certificate_reminder_days));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<{ message: string; fields: Record<string, string | undefined> } | null>(null);

  async function save() {
    if (!token) return;
    const validity = Number(months);
    const reminder = Number(days);
    const fields: Record<string, string> = {};
    if (!Number.isInteger(validity) || validity < 1 || validity > 24) fields.months = t("errorMonths");
    if (!Number.isInteger(reminder) || reminder < 0 || reminder > 90) fields.days = t("errorDays");
    if (Object.keys(fields).length > 0) {
      setError({ message: Object.values(fields)[0], fields });
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await saveDocumentSettings(token, {
        block_booking_on_unsigned: block,
        health_certificate_validity_months: validity,
        health_certificate_reminder_days: reminder,
      });
      onSaved();
    } catch (err) {
      setError(documentError(err, t, i18n));
    } finally {
      setBusy(false);
    }
  }

  const numberField = (id: "months" | "days", label: string, value: string, set: (value: string) => void, max: number, min: number) => (
    <label className="flex flex-col gap-1 text-xs font-semibold" style={{ color: "var(--dim)" }}>
      {label}
      <input
        type="number"
        inputMode="numeric"
        min={min}
        max={max}
        value={value}
        onChange={(event) => {
          set(event.target.value);
          setError(null);
        }}
        aria-invalid={Boolean(error?.fields[id])}
        className={`${inputClass} max-w-32`}
        style={{ ...inputStyle, ...(error?.fields[id] ? { borderColor: "var(--danger-border)" } : {}) }}
      />
      {error?.fields[id] ? <ErrorNotice variant="field">{error.fields[id]}</ErrorNotice> : null}
    </label>
  );

  return (
    <Dialog
      onClose={onClose}
      title={t("settingsTitle")}
      size="md"
      variant="sheet"
      testId="documents-settings-dialog"
      dismissible={!busy}
      onSubmit={(event) => {
        event.preventDefault();
        void save();
      }}
      error={error && !error.fields.months && !error.fields.days ? <ErrorNotice>{error.message}</ErrorNotice> : null}
      footer={
        <button type="submit" disabled={busy} className={primaryButtonClass} style={primaryButtonStyle}>
          {busy ? t("saving") : t("save")}
        </button>
      }
    >
      <div className="flex flex-col gap-3">
        <SettingRow label={t("gateLabel")} hint={t("gateHint")}>
          <Toggle label={t("gateLabel")} checked={block} onChange={setBlock} />
        </SettingRow>
        {numberField("months", t("validityMonths"), months, setMonths, 24, 1)}
        {numberField("days", t("reminderDays"), days, setDays, 90, 0)}
        <Hint>{t("settingsHealthHint")}</Hint>
      </div>
    </Dialog>
  );
}
