"use client";

import { useQuery } from "@tanstack/react-query";
import { useState } from "react";
import { useLocale, useTranslations } from "next-intl";

import {
  fetchPendingRequests,
  fetchSignatureEvidence,
  fetchSignatures,
  requestSignatures,
  setDocumentRequirement,
  type DocumentRequirement,
  type DocumentSettings,
  type DocumentTemplate,
  type OutstandingRow,
  type RequestResult,
} from "@/api/documents";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";
import { primaryButtonClass, primaryButtonStyle, secondaryButtonClass, secondaryButtonStyle } from "@/components/staff/staff-ui";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";
import { useOrganizationSlug } from "@/lib/organization-slug";

import { documentError } from "../document-errors";
import { blocksBookingOnPublish, requestedAtByUser, shortDate } from "../documents-model";
import { documentKeys, openLink, useDocumentsAccess, useToken } from "../use-documents";
import { RequirementPicker } from "./NewDocumentDialog";
import { PublishConfirm } from "./PublishConfirm";
import { RequestDialog } from "./RequestDialog";
import { BookingBlockWarning, Card, Hint, linkButtonClass, PersonRow, Toast } from "./staff-parts";
import { VersionDialog } from "./VersionDialog";

const SHOWN_SIGNATURES = 10;

/**
 * One document's side panel (mockup s7 B, `sideP`): its version, who is
 * missing with when they were asked, «Υπενθύμιση σε όλους», whether it is
 * «Υποχρεωτικό» or «Προαιρετικό», «Νέα έκδοση κειμένου» and who signed, each
 * with the certificate PDF.
 */
export function DocumentPanel({
  template,
  outstanding,
  clients,
  settings,
  canManage,
  onClose,
  onChanged,
}: {
  template: DocumentTemplate;
  outstanding: OutstandingRow | undefined;
  /** Clients of the box, for the confirm before a major version. */
  clients: number | null;
  settings: DocumentSettings | null | undefined;
  canManage: boolean;
  onClose: () => void;
  onChanged: () => void;
}) {
  const t = useTranslations("Documents");
  const i18n = useUiTranslations();
  const locale = useLocale();
  const token = useToken();
  const slug = useOrganizationSlug();
  const [sent, setSent] = useState<RequestResult | null>(null);
  const [sentTo, setSentTo] = useState<Set<string>>(() => new Set());
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [requirement, setRequirement] = useState<DocumentRequirement>(template.requirement);
  const [justMandatory, setJustMandatory] = useState(false);
  const [confirmMandatory, setConfirmMandatory] = useState(false);
  const [saving, setSaving] = useState(false);
  const access = useDocumentsAccess();
  const [versionOpen, setVersionOpen] = useState(false);
  const [requestOpen, setRequestOpen] = useState(false);
  const [allSignatures, setAllSignatures] = useState(false);

  const requests = useQuery({
    queryKey: [...documentKeys.all(slug), "pending", template.id],
    enabled: Boolean(token),
    queryFn: () => fetchPendingRequests(token!, template.id),
  });
  const signatures = useQuery({
    queryKey: [...documentKeys.all(slug), "signatures", template.id],
    enabled: Boolean(token),
    queryFn: () => fetchSignatures(token!, { template_id: template.id }),
  });

  const askedAt = requestedAtByUser(requests.data ?? []);
  const missing = outstanding?.clients ?? [];
  const mandatory = requirement === "mandatory";
  const lastVersion = template.versions?.find((version) => version.id === template.current_version_id);

  async function remindAll() {
    if (!token) return;
    setBusy("all");
    setError(null);
    try {
      const result = await requestSignatures(token, template.id, { audience: "all_clients" });
      setSent(result);
      void requests.refetch();
      onChanged();
    } catch (err) {
      setError(documentError(err, t, i18n).message);
    } finally {
      setBusy(null);
    }
  }

  async function ask(userId: string) {
    if (!token) return;
    setBusy(userId);
    setError(null);
    try {
      await requestSignatures(token, template.id, { audience: "person", user_id: userId });
      setSentTo((current) => new Set(current).add(userId));
      void requests.refetch();
    } catch (err) {
      setError(documentError(err, t, i18n).message);
    } finally {
      setBusy(null);
    }
  }

  async function changeRequirement(next: DocumentRequirement, confirmed = false) {
    if (!token || next === requirement) return;
    // Mandatory blocks the clients who have not signed at once: confirm first.
    if (next === "mandatory" && !confirmed && blocksBookingOnPublish("mandatory", settings)) {
      setConfirmMandatory(true);
      return;
    }
    const previous = requirement;
    setRequirement(next);
    setConfirmMandatory(false);
    setSaving(true);
    setError(null);
    try {
      await setDocumentRequirement(token, template.id, next);
      setJustMandatory(next === "mandatory");
      onChanged();
    } catch (err) {
      setRequirement(previous);
      setError(documentError(err, t, i18n).message);
    } finally {
      setSaving(false);
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

  const signatureRows = signatures.data ?? [];
  const shownSignatures = allSignatures ? signatureRows : signatureRows.slice(0, SHOWN_SIGNATURES);

  return (
    <>
      <SidePanel title={template.title} subtitle={t(mandatory ? "mandatory" : "optional")} onClose={onClose}>
        <Hint>
          {t("versionNumber", { number: template.current_version_number })}
          {lastVersion ? ` · ${shortDate(lastVersion.published_at, locale)}` : ""}
        </Hint>

        {missing.length > 0 ? (
          <section className="flex flex-col gap-2" data-testid="missing-list">
            <b className="text-sm" style={{ color: "var(--text)" }}>
              {mandatory ? t("missingCount", { count: missing.length }) : t("notSignedCount", { count: missing.length })}
            </b>
            <ul>
              {missing.map((client) => {
                const asked = askedAt.get(client.user_id);
                const detail = asked
                  ? t("askedOn", { date: shortDate(asked, locale) })
                  : client.status === "resign_required"
                    ? t("detailResign")
                    : t("notAsked");
                return (
                  <PersonRow
                    key={client.user_id}
                    name={client.display_name ?? client.handle ?? t("clientFallback")}
                    detail={detail}
                    action={
                      asked || sentTo.has(client.user_id) ? null : (
                        <button
                          type="button"
                          disabled={busy !== null}
                          onClick={() => void ask(client.user_id)}
                          className={secondaryButtonClass}
                          style={secondaryButtonStyle}
                        >
                          {t("askOne")}
                        </button>
                      )
                    }
                  />
                );
              })}
            </ul>
            {sent ? (
              <Toast>{sent.created > 0 ? t("remindSent", { count: sent.created }) : t("remindNobodyNew")}</Toast>
            ) : (
              <button type="button" onClick={() => void remindAll()} disabled={busy !== null} className={`${primaryButtonClass} self-start`} style={primaryButtonStyle}>
                {t("remindAll", { count: missing.length })}
              </button>
            )}
          </section>
        ) : (
          <p className="text-sm font-semibold" style={{ color: "var(--success)" }}>
            ✓ {t("allOk")}
          </p>
        )}

        <button type="button" onClick={() => setRequestOpen(true)} className={`${linkButtonClass} self-start`} style={{ color: "var(--primary)" }}>
          {t("requestMore")} ›
        </button>

        {error ? <ErrorNotice>{error}</ErrorNotice> : null}

        {canManage ? (
          <Card className="flex flex-col gap-2 py-3">
            <RequirementPicker value={requirement} onChange={(next) => void changeRequirement(next)} />
            {confirmMandatory ? (
              <PublishConfirm
                count={outstanding ? outstanding.outstanding : null}
                confirmLabel={t("confirmMandatory")}
                busyLabel={t("saving")}
                busy={saving}
                onBack={() => setConfirmMandatory(false)}
                onConfirm={() => void changeRequirement("mandatory", true)}
              />
            ) : null}
            {justMandatory && blocksBookingOnPublish("mandatory", settings) ? <BookingBlockWarning>{t("mandatoryBlocksBooking")}</BookingBlockWarning> : null}
            {mandatory && settings && !settings.block_booking_on_unsigned ? <Hint>{t("gateOffHint")}</Hint> : null}
          </Card>
        ) : null}

        {canManage ? (
          <div className="flex flex-col gap-1">
            <button type="button" onClick={() => setVersionOpen(true)} className={`${linkButtonClass} self-start`} style={{ color: "var(--primary)" }}>
              {t("newVersion")} ›
            </button>
            <Hint>{t("newVersionHint")}</Hint>
          </div>
        ) : null}

        {signatureRows.length > 0 ? (
          <section className="flex flex-col gap-1" data-testid="signed-list">
            <b className="text-sm" style={{ color: "var(--text)" }}>
              {t("signedCount", { count: outstanding?.signed ?? signatureRows.length })}
            </b>
            <ul>
              {shownSignatures.map((signature) => (
                <PersonRow
                  key={signature.id}
                  name={String(signature.account?.nickname ?? signature.account?.display_name ?? signature.typed_name ?? t("clientFallback"))}
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
            {signatureRows.length > SHOWN_SIGNATURES && !allSignatures ? (
              <button type="button" onClick={() => setAllSignatures(true)} className={`${linkButtonClass} self-start`} style={{ color: "var(--text-soft)" }}>
                {t("showAll", { count: signatureRows.length })}
              </button>
            ) : null}
          </section>
        ) : null}
      </SidePanel>

      {versionOpen ? (
        <VersionDialog
          template={template}
          settings={settings}
          clients={clients}
          onClose={() => setVersionOpen(false)}
          onPublished={() => {
            setVersionOpen(false);
            onChanged();
          }}
        />
      ) : null}
      {requestOpen ? (
        <RequestDialog
          template={template}
          onClose={() => setRequestOpen(false)}
          onSent={(result) => {
            setRequestOpen(false);
            setSent(result);
            void requests.refetch();
            onChanged();
          }}
        />
      ) : null}
    </>
  );
}
