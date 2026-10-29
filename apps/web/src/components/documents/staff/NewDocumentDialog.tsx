"use client";

import { useQuery } from "@tanstack/react-query";
import { useState, type FormEvent } from "react";
import { useLocale, useTranslations } from "next-intl";

import {
  createDocumentTemplate,
  fetchStarterDocuments,
  type DocumentKind,
  type DocumentRequirement,
  type DocumentSettings,
  type StarterDocument,
} from "@/api/documents";
import { Segmented } from "@/components/admin/finance/packages/package-ui";
import { inputClass, inputStyle, primaryButtonClass, primaryButtonStyle } from "@/components/staff/staff-ui";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { useUiTranslations } from "@/i18n/ui";

import { documentError } from "../document-errors";
import { blocksBookingOnPublish, DOCUMENT_KINDS } from "../documents-model";
import { useToken } from "../use-documents";
import { PublishConfirm } from "./PublishConfirm";
import { BookingBlockWarning, Hint, Notice, Pill } from "./staff-parts";

const LANGUAGES = ["el", "en", "de", "fr", "es", "it", "ru", "pt-PT", "nl", "bg", "ar", "he"];

type Draft = { kind: DocumentKind; title: string; body: string; requirement: DocumentRequirement; language: string; starter: boolean };

/**
 * «Νέο έγγραφο»: start from a Palee starter (always a draft for legal
 * review, ADR-252 §9) or from a blank page, then publish version 1 as
 * mandatory or optional.
 */
export function NewDocumentDialog({
  settings,
  clients,
  onClose,
  onCreated,
}: {
  settings: DocumentSettings | null | undefined;
  /** Clients of the box: a new mandatory document blocks all of them until they sign. */
  clients: number | null;
  onClose: () => void;
  onCreated: (templateId: string) => void;
}) {
  const t = useTranslations("Documents");
  const i18n = useUiTranslations();
  const locale = useLocale();
  const token = useToken();
  const starterLanguage = locale === "el" ? "el" : "en";
  const [draft, setDraft] = useState<Draft | null>(null);
  const [busy, setBusy] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [error, setError] = useState<{ message: string; fields: Record<string, string | undefined> } | null>(null);

  const starters = useQuery({
    queryKey: ["documents", "starters", starterLanguage],
    enabled: Boolean(token),
    staleTime: Infinity,
    queryFn: () => fetchStarterDocuments(token!, starterLanguage),
  });

  function fromStarter(starter: StarterDocument) {
    setDraft({ kind: starter.kind, title: starter.title, body: starter.body, requirement: starter.requirement, language: starter.language, starter: true });
  }

  function blank() {
    setDraft({ kind: "terms", title: "", body: "", requirement: "mandatory", language: LANGUAGES.includes(locale) ? locale : "en", starter: false });
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!token || !draft) return;
    const fields: Record<string, string> = {};
    if (!draft.title.trim()) fields.title = t("errorTitleRequired");
    if (!draft.body.trim()) fields.body = t("errorBodyRequired");
    if (Object.keys(fields).length > 0) {
      setError({ message: Object.values(fields)[0], fields });
      return;
    }
    // A mandatory document blocks bookings at once: say how many first.
    if (blocksBookingOnPublish(draft.requirement, settings) && !confirming) {
      setConfirming(true);
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const result = await createDocumentTemplate(token, {
        kind: draft.kind,
        title: draft.title.trim(),
        body: draft.body,
        requirement: draft.requirement,
        language: draft.language,
      });
      onCreated(result.template.id);
    } catch (err) {
      setError(documentError(err, t, i18n));
    } finally {
      setBusy(false);
    }
  }

  if (!draft) {
    return (
      <Dialog onClose={onClose} title={t("newDocument")} size="lg" variant="sheet" testId="new-document-dialog">
        <div className="flex flex-col gap-3">
          <Hint>{t("startersHint")}</Hint>
          {starters.isError ? <ErrorNotice>{documentError(starters.error, t, i18n).message}</ErrorNotice> : null}
          <ul className="flex flex-col gap-2">
            {(starters.data ?? []).map((starter) => (
              <li key={`${starter.kind}-${starter.language}`}>
                <button
                  type="button"
                  onClick={() => fromStarter(starter)}
                  className="flex w-full items-center justify-between gap-3 rounded-2xl px-4 py-3 text-left"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
                >
                  <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                    {starter.title}
                  </span>
                  {starter.legal_review_required || starter.draft ? <Pill tone="warning">{t("draftForLegalReview")}</Pill> : null}
                </button>
              </li>
            ))}
            <li>
              <button
                type="button"
                onClick={blank}
                className="flex w-full items-center rounded-2xl px-4 py-3 text-left text-sm font-semibold"
                style={{ border: "1px dashed var(--border-strong)", color: "var(--text-soft)" }}
              >
                {t("blankDocument")}
              </button>
            </li>
          </ul>
        </div>
      </Dialog>
    );
  }

  const set = (change: Partial<Draft>) => {
    setDraft({ ...draft, ...change });
    setError(null);
    setConfirming(false);
  };

  return (
    <Dialog
      onClose={onClose}
      title={t("newDocument")}
      size="2xl"
      variant="sheet"
      testId="new-document-dialog"
      dismissible={!busy}
      onSubmit={(event) => void submit(event)}
      error={error && !error.fields.title && !error.fields.body ? <ErrorNotice>{error.message}</ErrorNotice> : null}
      footer={
        confirming ? (
          <PublishConfirm count={clients} confirmLabel={t("confirmPublish")} busy={busy} onBack={() => setConfirming(false)} />
        ) : (
          <button type="submit" disabled={busy} className={primaryButtonClass} style={primaryButtonStyle}>
            {busy ? t("publishing") : t("publish")}
          </button>
        )
      }
    >
      <div className="flex flex-col gap-3">
        {draft.starter ? <Notice icon="⚖️" testId="draft-banner">{t("draftBanner")}</Notice> : null}
        <label className="flex flex-col gap-1 text-xs font-semibold" style={{ color: "var(--dim)" }}>
          {t("fieldTitle")}
          <input
            value={draft.title}
            onChange={(event) => set({ title: event.target.value })}
            maxLength={200}
            aria-invalid={Boolean(error?.fields.title)}
            className={inputClass}
            style={{ ...inputStyle, ...(error?.fields.title ? { borderColor: "var(--danger-border)" } : {}) }}
          />
        </label>
        {error?.fields.title ? <ErrorNotice variant="field">{error.fields.title}</ErrorNotice> : null}
        <div className="flex flex-col gap-1 text-xs font-semibold" style={{ color: "var(--dim)" }}>
          {t("fieldKind")}
          <Select value={draft.kind} onValueChange={(value) => set({ kind: value as DocumentKind })} aria-label={t("fieldKind")}>
            {DOCUMENT_KINDS.map((kind) => (
              <option key={kind} value={kind}>
                {t(`kind_${kind}`)}
              </option>
            ))}
          </Select>
        </div>
        <label className="flex flex-col gap-1 text-xs font-semibold" style={{ color: "var(--dim)" }}>
          {t("fieldBody")}
          <textarea
            value={draft.body}
            onChange={(event) => set({ body: event.target.value })}
            rows={12}
            maxLength={100_000}
            aria-invalid={Boolean(error?.fields.body)}
            className={`${inputClass} font-normal leading-6`}
            style={{ ...inputStyle, ...(error?.fields.body ? { borderColor: "var(--danger-border)" } : {}) }}
          />
        </label>
        {error?.fields.body ? <ErrorNotice variant="field">{error.fields.body}</ErrorNotice> : null}
        <RequirementPicker value={draft.requirement} onChange={(requirement) => set({ requirement })} />
        {blocksBookingOnPublish(draft.requirement, settings) ? <BookingBlockWarning>{t("publishBlocksBooking")}</BookingBlockWarning> : null}
      </div>
    </Dialog>
  );
}

/** «Υποχρεωτικό» / «Προαιρετικό» with what each means. */
export function RequirementPicker({ value, onChange }: { value: DocumentRequirement; onChange: (value: DocumentRequirement) => void }) {
  const t = useTranslations("Documents");
  return (
    <div className="flex flex-col gap-1.5">
      <Segmented
        label={t("requirementLabel")}
        value={value}
        onChange={onChange}
        options={[
          { value: "mandatory", label: t("mandatory") },
          { value: "optional", label: t("optional") },
        ]}
      />
      <Hint>{value === "mandatory" ? t("mandatoryHint") : t("optionalHint")}</Hint>
    </div>
  );
}
