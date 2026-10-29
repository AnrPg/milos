"use client";

import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { useLocale, useTranslations } from "next-intl";

import {
  fetchClientHealthCertificates,
  fetchClientHealthFile,
  recordClientHealthCertificate,
  requestClientHealthUpload,
  saveDocumentSettings,
  type DocumentSettings,
  type HealthList,
  type HealthRow,
} from "@/api/documents";
import { Toggle } from "@/components/admin/finance/packages/package-ui";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";
import { secondaryButtonClass, secondaryButtonStyle } from "@/components/staff/staff-ui";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";

import { documentError } from "../document-errors";
import { healthOutstanding, shortDate } from "../documents-model";
import { HealthUpload, validUntilText } from "../HealthUpload";
import { openLink, useDocumentsAccess, useToken } from "../use-documents";
import { Card, Hint, PersonRow, Pill, SettingRow } from "./staff-parts";

function healthTone(status: HealthRow["status"]) {
  return status === "valid" ? "success" : status === "expiring" ? "warning" : "danger";
}

/**
 * «Βεβαίωση υγείας» side panel (mockup s7 B, ADR-252 §5). Staff with
 * `manage_health_certificates` see who is missing with the dates and open a
 * client's certificates; coaches (`view_health`) see only «Ισχύει» or
 * «Έληξε» for their own clients. Staff who run the settings choose whether
 * the box asks for it and whether it blocks booking.
 */
export function HealthPanel({
  health,
  settings,
  canManage,
  onClose,
  onChanged,
}: {
  health: HealthList;
  settings: DocumentSettings | null | undefined;
  canManage: boolean;
  onClose: () => void;
  onChanged: () => void;
}) {
  const t = useTranslations("Documents");
  const i18n = useUiTranslations();
  const locale = useLocale();
  const token = useToken();
  const [person, setPerson] = useState<HealthRow | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const full = health.full_access;
  const missing = healthOutstanding(health.health_certificates);
  const expiring = health.health_certificates.filter((row) => row.status === "expiring");
  const months = settings?.health_certificate_validity_months ?? 12;

  async function save(change: Partial<DocumentSettings>) {
    if (!token) return;
    setSaving(true);
    setError(null);
    try {
      await saveDocumentSettings(token, change);
      onChanged();
    } catch (err) {
      setError(documentError(err, t, i18n).message);
    } finally {
      setSaving(false);
    }
  }

  function detail(row: HealthRow) {
    if (!full) return row.status === "missing" ? t("healthMissingShort") : row.status === "expired" ? t("healthExpiredShort") : t("healthValidShort");
    const certificate = row.certificate;
    if (row.status === "missing" || !certificate) return t("healthDetailMissing");
    if (row.status === "expired") return t("healthDetailExpired", { date: shortDate(certificate.expires_on, locale) });
    return t("healthDetailValid", { date: validUntilText(certificate, locale) });
  }

  const rowAction = (row: HealthRow) =>
    full ? (
      <button type="button" onClick={() => setPerson(row)} className={secondaryButtonClass} style={secondaryButtonStyle}>
        {t("open")}
      </button>
    ) : null;

  return (
    <>
      <SidePanel title={t("healthTitle")} subtitle={health.required ? t("mandatory") : t("notAskedFor")} onClose={onClose}>
        <Hint>{t("healthValidity", { count: months })}</Hint>

        {full ? (
          missing.length > 0 ? (
            <section className="flex flex-col gap-1" data-testid="health-missing">
              <b className="text-sm" style={{ color: "var(--text)" }}>
                {t("missingCount", { count: missing.length })}
              </b>
              <ul>
                {missing.map((row) => (
                  <PersonRow key={row.user_id} name={row.display_name ?? row.handle ?? t("clientFallback")} detail={detail(row)} action={rowAction(row)} />
                ))}
              </ul>
            </section>
          ) : (
            <p className="text-sm font-semibold" style={{ color: "var(--success)" }}>
              ✓ {t("allOk")}
            </p>
          )
        ) : (
          <ul data-testid="health-status-list">
            {health.health_certificates.map((row) => (
              <PersonRow
                key={row.user_id}
                name={row.display_name ?? row.handle ?? t("clientFallback")}
                action={<Pill tone={healthTone(row.status)}>{detail(row)}</Pill>}
              />
            ))}
          </ul>
        )}

        {full && expiring.length > 0 ? (
          <section className="flex flex-col gap-1">
            <b className="text-sm" style={{ color: "var(--text)" }}>
              {t("expiringCount", { count: expiring.length })}
            </b>
            <ul>
              {expiring.map((row) => (
                <PersonRow key={row.user_id} name={row.display_name ?? row.handle ?? t("clientFallback")} detail={detail(row)} action={rowAction(row)} />
              ))}
            </ul>
            <Hint>{t("healthAutoReminder")}</Hint>
          </section>
        ) : null}

        {error ? <ErrorNotice>{error}</ErrorNotice> : null}

        {canManage && settings ? (
          <Card>
            <SettingRow label={t("healthAskedFor")} hint={t("healthAskedForHint")}>
              <Toggle
                label={t("healthAskedFor")}
                checked={settings.health_certificate_required}
                disabled={saving}
                onChange={(value) =>
                  void save(value ? { health_certificate_required: true } : { health_certificate_required: false, block_booking_on_health_certificate: false })
                }
              />
            </SettingRow>
            <SettingRow label={t("blocksBooking")} hint={t("healthBlocksHint")}>
              <Toggle
                label={t("blocksBooking")}
                checked={settings.block_booking_on_health_certificate}
                disabled={saving}
                onChange={(value) => void save({ block_booking_on_health_certificate: value })}
              />
            </SettingRow>
          </Card>
        ) : null}

        <Hint>
          <span aria-hidden="true">🔒 </span>
          {t("healthStaffPrivacy")}
        </Hint>
      </SidePanel>

      {person ? <ClientHealthDialog person={person} onClose={() => setPerson(null)} onChanged={onChanged} /> : null}
    </>
  );
}

/** One client's certificates (full access only): dates, the file (each look is audited) and an upload on their behalf. */
export function ClientHealthDialog({
  person,
  onClose,
  onChanged,
}: {
  person: Pick<HealthRow, "user_id" | "display_name" | "handle">;
  onClose: () => void;
  onChanged: () => void;
}) {
  const t = useTranslations("Documents");
  const i18n = useUiTranslations();
  const locale = useLocale();
  const token = useToken();
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const canUpload = useDocumentsAccess().healthWrite;
  const certificates = useQuery({
    queryKey: ["documents", "client-health", person.user_id],
    enabled: Boolean(token),
    queryFn: () => fetchClientHealthCertificates(token!, person.user_id),
  });
  const api = {
    reserve: (accessToken: string, contentType: Parameters<typeof requestClientHealthUpload>[2]) =>
      requestClientHealthUpload(accessToken, person.user_id, contentType),
    record: (accessToken: string, input: Omit<Parameters<typeof recordClientHealthCertificate>[1], "user_id">) =>
      recordClientHealthCertificate(accessToken, { ...input, user_id: person.user_id }),
  };

  async function openFile(id: string) {
    setError(null);
    try {
      await openLink(() => fetchClientHealthFile(token!, id));
    } catch (err) {
      setError(documentError(err, t, i18n).message);
    }
  }

  return (
    <Dialog onClose={onClose} title={person.display_name ?? person.handle ?? t("clientFallback")} eyebrow={t("healthTitle")} size="md" variant="sheet" testId="client-health-dialog">
      {uploading ? (
        <HealthUpload
          api={api}
          subtitle={t("healthUploadForClient")}
          onUploaded={() => {
            setUploading(false);
            void certificates.refetch();
            onChanged();
          }}
        />
      ) : (
        <div className="flex flex-col gap-3">
          {certificates.isError ? <ErrorNotice>{documentError(certificates.error, t, i18n).message}</ErrorNotice> : null}
          {certificates.data && certificates.data.length === 0 ? <Hint>{t("healthDetailMissing")}</Hint> : null}
          <ul>
            {(certificates.data ?? []).map((certificate) => (
              <PersonRow
                key={certificate.id}
                name={t("healthDetailValid", { date: validUntilText(certificate, locale) })}
                detail={t("healthIssued", { date: shortDate(certificate.issued_on, locale) })}
                action={
                  <button type="button" onClick={() => void openFile(certificate.id)} className={secondaryButtonClass} style={secondaryButtonStyle}>
                    {t("openFile")}
                  </button>
                }
              />
            ))}
          </ul>
          {error ? <ErrorNotice>{error}</ErrorNotice> : null}
          {canUpload ? (
            <button type="button" onClick={() => setUploading(true)} className="self-start text-sm font-semibold" style={{ color: "var(--primary)" }}>
              {t("healthUploadNew")} ›
            </button>
          ) : null}
        </div>
      )}
    </Dialog>
  );
}
