"use client";

import { useQueryClient } from "@tanstack/react-query";
import { useId, useRef, useState } from "react";
import { useLocale, useTranslations } from "next-intl";

import type { HealthCertificate, HealthContentType, PresignedUpload } from "@/api/documents";
import { DateInput } from "@/components/ui/DateInput";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";
import { putPresigned } from "@/lib/presigned-upload";
import { useOrganizationSlug } from "@/lib/organization-slug";

import { documentError } from "./document-errors";
import { HEALTH_MAX_BYTES, healthContentType, isoToday, lastValidDay, shortDate } from "./documents-model";
import { documentKeys, useToken } from "./use-documents";

export type HealthUploadApi = {
  reserve: (token: string, contentType: HealthContentType) => Promise<PresignedUpload>;
  record: (token: string, input: { file_key: string; content_type: HealthContentType; issued_on: string }) => Promise<HealthCertificate>;
};

/**
 * Health certificate upload (mockup s7 `uploadPage`): photograph the
 * certificate or choose a file, give the issue date, «Αποστολή». The client
 * uploads their own; staff with `manage_health_certificates` upload for a
 * client through the same form (`api`). Palee keeps only the dates and the
 * file (ADR-252 §5).
 */
export function HealthUpload({
  api,
  onUploaded,
  subtitle,
}: {
  api: HealthUploadApi;
  onUploaded: (certificate: HealthCertificate) => void;
  subtitle?: string;
}) {
  const t = useTranslations("Documents");
  const i18n = useUiTranslations();
  const token = useToken();
  const slug = useOrganizationSlug();
  const queryClient = useQueryClient();
  const inputRef = useRef<HTMLInputElement>(null);
  const dateId = useId();
  const [file, setFile] = useState<File | null>(null);
  const [issuedOn, setIssuedOn] = useState("");
  const [busy, setBusy] = useState(false);
  const [fileError, setFileError] = useState<string | null>(null);
  const [error, setError] = useState<{ message: string; fields: Record<string, string | undefined> } | null>(null);

  function choose(next: File | null) {
    setError(null);
    if (!next) return;
    if (!healthContentType(next)) {
      setFileError(t("errorFileInvalid"));
      return;
    }
    if (next.size > HEALTH_MAX_BYTES) {
      setFileError(t("errorFileTooLarge"));
      return;
    }
    setFileError(null);
    setFile(next);
  }

  async function submit() {
    const contentType = file ? healthContentType(file) : null;
    if (!token || !file || !contentType || !issuedOn) return;
    setBusy(true);
    setError(null);
    try {
      const upload = await api.reserve(token, contentType);
      await putPresigned(upload.upload_url, file, upload.required_headers);
      const certificate = await api.record(token, { file_key: upload.file_key, content_type: contentType, issued_on: issuedOn });
      await queryClient.invalidateQueries({ queryKey: documentKeys.all(slug) });
      onUploaded(certificate);
    } catch (err) {
      setError(documentError(err, t, i18n));
    } finally {
      setBusy(false);
    }
  }

  const issuedError = error?.fields.issued_on ?? error?.fields.expires_on;

  return (
    <div className="flex flex-col gap-3" data-testid="health-upload">
      <div>
        <h2 className="text-lg font-bold" style={{ color: "var(--text)" }}>
          {t("healthTitle")}
        </h2>
        <p className="text-xs" style={{ color: "var(--dim)" }}>
          {subtitle ?? t("healthSubtitle")}
        </p>
      </div>
      <button
        type="button"
        onClick={() => inputRef.current?.click()}
        className="flex min-h-28 flex-col items-center justify-center gap-1 rounded-2xl px-4 py-5 text-center"
        style={{
          background: "var(--panel-raised)",
          border: `1.5px dashed ${fileError ? "var(--danger-border)" : file ? "var(--primary)" : "var(--border-strong)"}`,
          color: "var(--text)",
        }}
      >
        <span aria-hidden="true" className="text-2xl">
          {file ? "✓" : "📷"}
        </span>
        <b className="text-sm">{file ? file.name : t("healthPhoto")}</b>
        {file ? null : (
          <span className="text-xs" style={{ color: "var(--dim)" }}>
            {t("healthChooseFile")}
          </span>
        )}
      </button>
      <input
        ref={inputRef}
        type="file"
        accept="image/jpeg,image/png,image/webp,application/pdf"
        className="sr-only"
        aria-label={t("healthPhoto")}
        data-testid="health-file"
        onChange={(event) => choose(event.target.files?.[0] ?? null)}
      />
      {fileError ? <ErrorNotice variant="field">{fileError}</ErrorNotice> : null}
      <label htmlFor={dateId} className="text-xs font-semibold" style={{ color: "var(--dim)" }}>
        {t("healthIssuedOn")}
      </label>
      <DateInput
        id={dateId}
        value={issuedOn}
        onValueChange={(value) => {
          setIssuedOn(value);
          setError(null);
        }}
        max={isoToday()}
        aria-invalid={Boolean(issuedError)}
        style={issuedError ? { borderColor: "var(--danger-border)" } : undefined}
      />
      {issuedError ? (
        <ErrorNotice variant="field">{issuedError}</ErrorNotice>
      ) : (
        <p className="text-xs" style={{ color: "var(--dim)" }}>
          {t("healthReminderHint")}
        </p>
      )}
      <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>
        <span aria-hidden="true">🔒 </span>
        {t("healthPrivacy")}
      </p>
      {error && !issuedError ? <ErrorNotice>{error.message}</ErrorNotice> : null}
      <button
        type="button"
        onClick={() => void submit()}
        disabled={!file || !issuedOn || busy}
        className="min-h-12 w-full rounded-2xl text-base font-bold disabled:opacity-50"
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
      >
        {busy ? t("sending") : t("send")}
      </button>
    </div>
  );
}

/** «Ισχύει έως …» for a certificate (its last valid day). */
export function validUntilText(certificate: Pick<HealthCertificate, "expires_on">, locale: string) {
  return shortDate(lastValidDay(certificate.expires_on), locale);
}

export function useLocaleDate() {
  const locale = useLocale();
  return (value: string) => shortDate(value, locale);
}
