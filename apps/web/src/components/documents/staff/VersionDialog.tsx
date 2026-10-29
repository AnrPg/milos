"use client";

import { useQuery } from "@tanstack/react-query";
import { useEffect, useState, type FormEvent } from "react";
import { useTranslations } from "next-intl";

import { fetchDocumentVersion, publishDocumentVersion, type ChangeKind, type DocumentSettings, type DocumentTemplate } from "@/api/documents";
import { Segmented } from "@/components/admin/finance/packages/package-ui";
import { inputClass, inputStyle, primaryButtonClass, primaryButtonStyle } from "@/components/staff/staff-ui";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";

import { documentError } from "../document-errors";
import { blocksBookingOnPublish } from "../documents-model";
import { useToken } from "../use-documents";
import { BookingBlockWarning, Hint } from "./staff-parts";

/**
 * «Νέα έκδοση κειμένου»: edit the current text and publish it as a
 * «Ουσιαστική αλλαγή» (everyone signs again, the default) or a «Μικρή
 * διόρθωση» (signatures still count). Versions are never changed afterwards.
 */
export function VersionDialog({
  template,
  settings,
  onClose,
  onPublished,
}: {
  template: DocumentTemplate;
  settings: DocumentSettings | null | undefined;
  onClose: () => void;
  onPublished: () => void;
}) {
  const t = useTranslations("Documents");
  const i18n = useUiTranslations();
  const token = useToken();
  const [title, setTitle] = useState(template.title);
  const [body, setBody] = useState<string | null>(null);
  const [changeKind, setChangeKind] = useState<ChangeKind>("major");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<{ message: string; fields: Record<string, string | undefined> } | null>(null);

  const current = useQuery({
    queryKey: ["documents", "version", template.current_version_id],
    enabled: Boolean(token && template.current_version_id),
    queryFn: () => fetchDocumentVersion(token!, template.id, template.current_version_id!),
  });

  useEffect(() => {
    if (current.data && body === null) {
      setBody(current.data.body ?? "");
      setTitle(current.data.title || template.title);
    }
  }, [current.data, body, template.title]);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!token || body === null) return;
    if (!body.trim()) {
      setError({ message: t("errorBodyRequired"), fields: { body: t("errorBodyRequired") } });
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await publishDocumentVersion(token, template.id, { title: title.trim() || template.title, body, change_kind: changeKind });
      onPublished();
    } catch (err) {
      setError(documentError(err, t, i18n));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog
      onClose={onClose}
      title={t("newVersionTitle", { number: template.current_version_number + 1 })}
      eyebrow={template.title}
      size="2xl"
      variant="sheet"
      testId="version-dialog"
      dismissible={!busy}
      onSubmit={(event) => void submit(event)}
      error={error && !error.fields.body ? <ErrorNotice>{error.message}</ErrorNotice> : null}
      footer={
        <button type="submit" disabled={busy || body === null} className={primaryButtonClass} style={primaryButtonStyle}>
          {busy ? t("publishing") : t("publish")}
        </button>
      }
    >
      <div className="flex flex-col gap-3">
        {current.isError ? <ErrorNotice>{documentError(current.error, t, i18n).message}</ErrorNotice> : null}
        <label className="flex flex-col gap-1 text-xs font-semibold" style={{ color: "var(--dim)" }}>
          {t("fieldTitle")}
          <input value={title} onChange={(event) => setTitle(event.target.value)} maxLength={200} className={inputClass} style={inputStyle} />
        </label>
        <label className="flex flex-col gap-1 text-xs font-semibold" style={{ color: "var(--dim)" }}>
          {t("fieldBody")}
          <textarea
            value={body ?? ""}
            disabled={body === null}
            onChange={(event) => {
              setBody(event.target.value);
              setError(null);
            }}
            rows={12}
            maxLength={100_000}
            aria-invalid={Boolean(error?.fields.body)}
            className={`${inputClass} font-normal leading-6`}
            style={{ ...inputStyle, ...(error?.fields.body ? { borderColor: "var(--danger-border)" } : {}) }}
          />
        </label>
        {error?.fields.body ? <ErrorNotice variant="field">{error.fields.body}</ErrorNotice> : null}
        <Segmented
          label={t("changeKindLabel")}
          value={changeKind}
          onChange={setChangeKind}
          options={[
            { value: "major", label: t("changeMajor") },
            { value: "minor", label: t("changeMinor") },
          ]}
        />
        <Hint>{changeKind === "major" ? t("changeMajorHint") : t("changeMinorHint")}</Hint>
        {blocksBookingOnPublish(template.requirement, settings, changeKind) ? <BookingBlockWarning>{t("publishBlocksBooking")}</BookingBlockWarning> : null}
      </div>
    </Dialog>
  );
}
