"use client";

import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { useLocale, useTranslations } from "next-intl";

import { fetchHealthCertificates, fetchMemberDocuments, fetchSignatureEvidence, requestSignatures, type HealthStatus } from "@/api/documents";
import { secondaryButtonClass, secondaryButtonStyle } from "@/components/staff/staff-ui";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";
import { useOrganizationSlug } from "@/lib/organization-slug";

import { documentError } from "../document-errors";
import { shortDate } from "../documents-model";
import { useItemDetail } from "../MyDocuments";
import { documentKeys, openLink, useDocumentsAccess, useToken } from "../use-documents";
import { ClientHealthDialog } from "./HealthPanel";
import { PersonRow, Pill } from "./staff-parts";

/** Coaches and staff without the health capability see only valid or expired (ADR-252 §5). */
function shownHealth(status: HealthStatus, full: boolean): HealthStatus {
  return full ? status : status === "expiring" ? "valid" : status;
}

/**
 * A client's documents on their staff profile (ADR-252 §8 `members/:user_id`):
 * each document with its status and «Αίτημα» for one that is missing, their
 * signatures with the certificate PDF, and their health certificate.
 */
export function MemberDocumentsPanel({ userId, name }: { userId: string; name: string }) {
  const t = useTranslations("Documents");
  const i18n = useUiTranslations();
  const locale = useLocale();
  const token = useToken();
  const slug = useOrganizationSlug();
  const access = useDocumentsAccess();
  const detail = useItemDetail();
  const [asked, setAsked] = useState<Set<string>>(() => new Set());
  const [error, setError] = useState<string | null>(null);
  const [healthOpen, setHealthOpen] = useState(false);

  const member = useQuery({
    queryKey: documentKeys.member(slug, userId),
    enabled: Boolean(token && access.documents),
    queryFn: () => fetchMemberDocuments(token!, userId),
  });
  const health = useQuery({
    queryKey: documentKeys.health(slug),
    enabled: Boolean(token && access.health && !access.documents),
    queryFn: () => fetchHealthCertificates(token!),
  });

  if (!access.any) return null;

  const healthStatus = member.data?.health_certificate_status ?? health.data?.health_certificates.find((row) => row.user_id === userId)?.status ?? null;
  const titles = new Map((member.data?.documents ?? []).map((item) => [item.template_id, item.title]));
  const documents = (member.data?.documents ?? []).filter((item) => item.current_version_id);

  async function ask(templateId: string) {
    if (!token) return;
    setError(null);
    try {
      await requestSignatures(token, templateId, { audience: "person", user_id: userId });
      setAsked((current) => new Set(current).add(templateId));
    } catch (err) {
      setError(documentError(err, t, i18n).message);
    }
  }

  async function openCertificate(signatureId: string) {
    setError(null);
    try {
      await openLink(() => fetchSignatureEvidence(token!, signatureId));
    } catch (err) {
      setError(documentError(err, t, i18n).message);
    }
  }

  return (
    <section
      id="documents"
      aria-labelledby="member-documents-title"
      className="rounded-[2rem] p-5 md:p-6"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      data-testid="member-documents"
    >
      <h2 id="member-documents-title" className="text-xl font-semibold" style={{ color: "var(--text)" }}>
        {t("title")}
      </h2>
      {member.isError ? <ErrorNotice>{documentError(member.error, t, i18n).message}</ErrorNotice> : null}
      <ul className="mt-2">
        {documents.map((item) => (
          <PersonRow
            key={item.template_id}
            name={item.title}
            detail={detail(item)}
            action={
              item.status === "signed" ? (
                <Pill tone="success">✓</Pill>
              ) : item.requested || asked.has(item.template_id) ? (
                <Pill tone="neutral">{t("asked")}</Pill>
              ) : (
                <button type="button" onClick={() => void ask(item.template_id)} className={secondaryButtonClass} style={secondaryButtonStyle}>
                  {t("askOne")}
                </button>
              )
            }
          />
        ))}
        {healthStatus ? (
          <PersonRow
            name={t("healthTitle")}
            action={
              <span className="flex items-center gap-2">
                <Pill tone={shownHealth(healthStatus, access.healthFull) === "valid" ? "success" : shownHealth(healthStatus, access.healthFull) === "expiring" ? "warning" : "danger"}>
                  {t(`healthStatus_${shownHealth(healthStatus, access.healthFull)}`)}
                </Pill>
                {access.healthFull ? (
                  <button type="button" onClick={() => setHealthOpen(true)} className={secondaryButtonClass} style={secondaryButtonStyle}>
                    {t("open")}
                  </button>
                ) : null}
              </span>
            }
          />
        ) : null}
      </ul>
      {member.data && member.data.signatures.length > 0 ? (
        <>
          <h3 className="mt-4 text-sm font-bold" style={{ color: "var(--text)" }}>
            {t("signaturesHeading")}
          </h3>
          <ul>
            {member.data.signatures.map((signature) => (
              <PersonRow
                key={signature.id}
                name={titles.get(signature.template_id) ?? t("documentFallback")}
                detail={t("signedVersionOn", { number: signature.version_number, date: shortDate(signature.signed_at, locale) })}
                action={
                  access.evidence ? (
                    <button type="button" onClick={() => void openCertificate(signature.id)} className={secondaryButtonClass} style={secondaryButtonStyle}>
                      {t("certificatePdf")}
                    </button>
                  ) : null
                }
              />
            ))}
          </ul>
        </>
      ) : null}
      {error ? <ErrorNotice>{error}</ErrorNotice> : null}
      {healthOpen ? <ClientHealthDialog person={{ user_id: userId, display_name: name, handle: null }} onClose={() => setHealthOpen(false)} onChanged={() => void member.refetch()} /> : null}
    </section>
  );
}
