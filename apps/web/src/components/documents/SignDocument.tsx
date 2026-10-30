"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { useTranslations } from "next-intl";

import { fetchMyDocument, signMyDocument } from "@/api/documents";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";
import { useOrganizationSlug } from "@/lib/organization-slug";

import { documentError } from "./document-errors";
import { PAD_HEIGHT, PAD_WIDTH, typedNameValid } from "./documents-model";
import { SignaturePad } from "./SignaturePad";
import { documentKeys, useToken } from "./use-documents";

/**
 * Read and sign (mockup s7 `signPage`): the full text of the current
 * version, the signature box, then «Υπογράφω». A typed name can stand in for
 * the drawn signature or go with it (ADR-252 §3). Pressing «Υπογράφω» is the
 * agreement to the text, as the line above the button says.
 */
export function SignDocument({
  templateId,
  boxName,
  onSigned,
}: {
  templateId: string;
  boxName?: string | null;
  onSigned: () => void;
}) {
  const t = useTranslations("Documents");
  const i18n = useUiTranslations();
  const token = useToken();
  const slug = useOrganizationSlug();
  const queryClient = useQueryClient();
  const [strokes, setStrokes] = useState<number[][][]>([]);
  const [typedName, setTypedName] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<{ message: string; fields: Record<string, string | undefined> } | null>(null);

  const document = useQuery({
    queryKey: [...documentKeys.mine(slug), "document", templateId],
    enabled: Boolean(token),
    queryFn: () => fetchMyDocument(token!, templateId),
  });

  const nameOk = typedNameValid(typedName);
  const ready = strokes.length > 0 || nameOk;

  async function sign() {
    const version = document.data?.version;
    if (!token || !version || !ready) return;
    setBusy(true);
    setError(null);
    try {
      await signMyDocument(token, templateId, {
        version_id: version.id,
        agreed: true,
        ...(nameOk ? { typed_name: typedName.trim().replace(/\s+/g, " ") } : {}),
        ...(strokes.length > 0 ? { drawn_signature: { width: PAD_WIDTH, height: PAD_HEIGHT, strokes } } : {}),
      });
      await queryClient.invalidateQueries({ queryKey: documentKeys.mine(slug) });
      onSigned();
    } catch (err) {
      setError(documentError(err, t, i18n));
      // The text changed while it was read: show the new version.
      void document.refetch();
    } finally {
      setBusy(false);
    }
  }

  if (document.isPending) {
    return (
      <p className="py-6 text-sm" style={{ color: "var(--dim)" }}>
        {t("loading")}
      </p>
    );
  }
  if (document.isError || !document.data) {
    return <ErrorNotice>{documentError(document.error, t, i18n).message}</ErrorNotice>;
  }

  const { template, version } = document.data;

  return (
    <div className="flex flex-col gap-3" data-testid="sign-document">
      <div>
        <h2 className="text-lg font-bold" style={{ color: "var(--text)" }}>
          {version.title || template.title}
        </h2>
        <p className="text-xs" style={{ color: "var(--dim)" }}>
          {boxName ? `${boxName} · ` : ""}
          {t("versionNumber", { number: version.number })}
        </p>
      </div>
      <div
        className="max-h-[45dvh] overflow-y-auto whitespace-pre-line rounded-2xl px-4 py-3 text-sm leading-6"
        style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
        tabIndex={0}
        aria-label={t("documentText")}
      >
        {version.body}
      </div>
      <SignaturePad onChange={setStrokes} disabled={busy} />
      <label className="flex flex-col gap-1 text-xs font-semibold" style={{ color: "var(--dim)" }}>
        {t("typedNameLabel")}
        <input
          value={typedName}
          onChange={(event) => setTypedName(event.target.value)}
          maxLength={120}
          autoComplete="name"
          aria-invalid={Boolean(error?.fields.typed_name)}
          className="min-h-11 rounded-xl px-3 text-sm font-normal"
          style={{
            background: "var(--panel-muted)",
            border: `1px solid ${error?.fields.typed_name ? "var(--danger-border)" : "var(--border-strong)"}`,
            color: "var(--text)",
          }}
        />
      </label>
      {error?.fields.typed_name ? <ErrorNotice variant="field">{error.fields.typed_name}</ErrorNotice> : null}
      <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>
        {t("signEvidenceHint")}
      </p>
      {error && !error.fields.typed_name ? <ErrorNotice>{error.message}</ErrorNotice> : null}
      <p className="text-xs leading-5" style={{ color: "var(--text-soft)" }}>
        {t("signAgreement")}
      </p>
      <button
        type="button"
        onClick={() => void sign()}
        disabled={!ready || busy}
        className="min-h-12 w-full rounded-2xl text-base font-bold disabled:opacity-50"
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
      >
        {busy ? t("signing") : t("signAction")}
      </button>
    </div>
  );
}
