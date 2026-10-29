"use client";

import { useRouter } from "next/navigation";
import { useState, type ReactNode } from "react";
import { useLocale, useTranslations } from "next-intl";

import {
  fetchMyHealthFile,
  fetchMySignatureEvidence,
  recordMyHealthCertificate,
  requestMyHealthUpload,
  type DocumentItem,
  type MyDocumentsOverview,
} from "@/api/documents";
import { HubCard, HubList, HubPage } from "@/components/member-app/HubParts";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { BackLink } from "@/components/ui/BackLink";
import { useUiTranslations } from "@/i18n/ui";
import { useSelectedMembershipRole } from "@/lib/membership-role";

import { documentError } from "./document-errors";
import { myHealthOutstanding, shortDate, sortMyDocuments } from "./documents-model";
import { HealthUpload, validUntilText } from "./HealthUpload";
import { SignDocument } from "./SignDocument";
import { openLink, useMyDocuments, useMySignatures, useToken } from "./use-documents";

export const MY_HEALTH_API = { reserve: requestMyHealthUpload, record: recordMyHealthCertificate };

export function useBoxName() {
  const { membership } = useSelectedMembershipRole();
  return membership?.settings?.brand_name?.trim() || membership?.organization.name || null;
}

/** A small status mark: «Λείπει» in red, ✓ in green, or a neutral word. */
export function StatusMark({ tone, children }: { tone: "bad" | "ok" | "warn" | "neutral"; children: ReactNode }) {
  const color = tone === "bad" ? "var(--danger)" : tone === "ok" ? "var(--success)" : tone === "warn" ? "var(--warning)" : "var(--muted)";
  return (
    <span
      className="inline-flex shrink-0 items-center rounded-full px-2.5 py-0.5 text-xs font-bold"
      style={{ color, background: `color-mix(in srgb, ${color} 12%, transparent)` }}
    >
      {children}
    </span>
  );
}

/** What a document row says under its title. */
export function useItemDetail() {
  const t = useTranslations("Documents");
  const locale = useLocale();
  return (item: DocumentItem) => {
    if (item.status === "resign_required") return t("detailResign");
    if (item.status === "unsigned") return item.outstanding ? t("detailUnsigned") : item.requested ? t("detailRequested") : t("detailOptional");
    return item.signature ? t("detailSignedOn", { date: shortDate(item.signature.signed_at, locale) }) : t("detailOk");
  };
}

function DocRow({ item, onOpen }: { item: DocumentItem; onOpen?: () => void }) {
  const t = useTranslations("Documents");
  const detail = useItemDetail();
  const signed = item.status === "signed";
  const mark = signed ? (
    <StatusMark tone="ok">✓</StatusMark>
  ) : item.outstanding ? (
    <StatusMark tone="bad">{t("missing")}</StatusMark>
  ) : (
    <StatusMark tone="neutral">{t("optional")}</StatusMark>
  );
  const body = (
    <>
      <span className="flex min-w-0 flex-1 flex-col text-left">
        <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {item.title}
        </span>
        <span className="text-xs" style={{ color: "var(--dim)" }}>
          {detail(item)}
        </span>
      </span>
      {mark}
      {onOpen ? (
        <span aria-hidden="true" style={{ color: "var(--dim)" }}>
          ›
        </span>
      ) : null}
    </>
  );
  const className = "flex min-h-14 w-full items-center justify-between gap-3 px-5 py-3";
  const style = { borderTop: "1px solid var(--border)" };
  return onOpen ? (
    <button type="button" onClick={onOpen} className={className} style={style} data-testid={`my-doc-${item.template_id}`}>
      {body}
    </button>
  ) : (
    <div className={className} style={style} data-testid={`my-doc-${item.template_id}`}>
      {body}
    </div>
  );
}

function HealthRowView({ overview, onOpen }: { overview: MyDocumentsOverview; onOpen: () => void }) {
  const t = useTranslations("Documents");
  const locale = useLocale();
  const health = overview.health_certificate;
  const certificate = health.certificate;
  const missing = myHealthOutstanding(overview);
  const detail =
    health.status === "missing"
      ? t("healthDetailMissing")
      : health.status === "expired" && certificate
        ? t("healthDetailExpired", { date: shortDate(certificate.expires_on, locale) })
        : certificate
          ? t("healthDetailValid", { date: validUntilText(certificate, locale) })
          : t("healthDetailMissing");
  const mark = missing ? (
    <StatusMark tone="bad">{t("missing")}</StatusMark>
  ) : health.status === "expiring" ? (
    <StatusMark tone="warn">{t("expiresSoon")}</StatusMark>
  ) : health.status === "valid" ? (
    <StatusMark tone="ok">✓</StatusMark>
  ) : (
    <StatusMark tone="neutral">{t("optional")}</StatusMark>
  );
  return (
    <button
      type="button"
      onClick={onOpen}
      className="flex min-h-14 w-full items-center justify-between gap-3 px-5 py-3"
      style={{ borderTop: "1px solid var(--border)" }}
      data-testid="my-doc-health"
    >
      <span className="flex min-w-0 flex-1 flex-col text-left">
        <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("healthTitle")}
        </span>
        <span className="text-xs" style={{ color: "var(--dim)" }}>
          {detail}
        </span>
      </span>
      {mark}
      <span aria-hidden="true" style={{ color: "var(--dim)" }}>
        ›
      </span>
    </button>
  );
}

/**
 * Box › Έγγραφα: what the box asks the client to sign (outstanding first),
 * the health certificate when the box asks for one, and their signatures,
 * each with its certificate PDF. A row opens «read and sign» or the upload.
 */
export function MyDocuments() {
  const t = useTranslations("Documents");
  const i18n = useUiTranslations();
  const locale = useLocale();
  const router = useRouter();
  const token = useToken();
  const overview = useMyDocuments();
  const signatures = useMySignatures();
  const [linkError, setLinkError] = useState<string | null>(null);

  const titles = new Map((overview.data?.documents ?? []).map((item) => [item.template_id, item.title]));
  const documents = sortMyDocuments(overview.data?.documents ?? []);
  const health = overview.data?.health_certificate;
  const showHealth = Boolean(health && (health.required || health.certificate));

  async function open(load: () => Promise<{ url: string }>) {
    setLinkError(null);
    try {
      await openLink(load);
    } catch (error) {
      setLinkError(documentError(error, t, i18n).message);
    }
  }

  return (
    <HubPage title={t("title")} back={<BackLink href="/box">{t("backToBox")}</BackLink>}>
      {overview.isPending ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>
          {t("loading")}
        </p>
      ) : overview.isError ? (
        <ErrorNotice>{documentError(overview.error, t, i18n).message}</ErrorNotice>
      ) : documents.length === 0 && !showHealth ? (
        <HubCard>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>
            {t("noDocuments")}
          </p>
        </HubCard>
      ) : (
        <HubList>
          {documents.map((item) => (
            <DocRow
              key={item.template_id}
              item={item}
              onOpen={item.status === "signed" ? undefined : () => router.push(`/box/documents/${encodeURIComponent(item.template_id)}`)}
            />
          ))}
          {showHealth && overview.data ? <HealthRowView overview={overview.data} onOpen={() => router.push("/box/documents/health")} /> : null}
        </HubList>
      )}

      {signatures.data && signatures.data.length > 0 ? (
        <HubCard eyebrow={t("mySignatures")}>
          <ul className="flex flex-col gap-3">
            {signatures.data.map((signature) => (
              <li key={signature.id} className="flex items-center justify-between gap-3">
                <span className="flex min-w-0 flex-col">
                  <span className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
                    {titles.get(signature.template_id) ?? t("documentFallback")}
                  </span>
                  <span className="text-xs" style={{ color: "var(--dim)" }}>
                    {t("signedVersionOn", { number: signature.version_number, date: shortDate(signature.signed_at, locale) })}
                  </span>
                </span>
                <button
                  type="button"
                  onClick={() => void open(() => fetchMySignatureEvidence(token!, signature.id))}
                  className="min-h-10 shrink-0 rounded-full px-4 text-xs font-bold"
                  style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
                >
                  {t("certificatePdf")}
                </button>
              </li>
            ))}
          </ul>
        </HubCard>
      ) : null}

      {health?.certificate ? (
        <button
          type="button"
          onClick={() => void open(() => fetchMyHealthFile(token!, health.certificate!.id))}
          className="self-start text-sm font-semibold underline-offset-4 hover:underline"
          style={{ color: "var(--text-soft)" }}
        >
          {t("healthOpenFile")}
        </button>
      ) : null}
      {linkError ? <ErrorNotice>{linkError}</ErrorNotice> : null}
    </HubPage>
  );
}

/** Box › Έγγραφα › one document: read and sign, then back to the list. */
export function MySignPage({ templateId }: { templateId: string }) {
  const t = useTranslations("Documents");
  const router = useRouter();
  const boxName = useBoxName();
  return (
    <HubPage title={t("title")} back={<BackLink href="/box/documents">{t("title")}</BackLink>}>
      <HubCard>
        <SignDocument templateId={templateId} boxName={boxName} onSigned={() => router.push("/box/documents")} />
      </HubCard>
    </HubPage>
  );
}

/** Box › Έγγραφα › Βεβαίωση υγείας. */
export function MyHealthPage() {
  const t = useTranslations("Documents");
  const router = useRouter();
  return (
    <HubPage title={t("title")} back={<BackLink href="/box/documents">{t("title")}</BackLink>}>
      <HubCard>
        <HealthUpload api={MY_HEALTH_API} onUploaded={() => router.push("/box/documents")} />
      </HubCard>
    </HubPage>
  );
}
