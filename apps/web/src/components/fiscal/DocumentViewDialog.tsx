"use client";

import { useMutation, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import {
  DOCUMENT_LANGUAGES,
  fetchDocumentHtml,
  fetchDocumentPdf,
  saveBlob,
  type DocumentLanguage,
  type FiscalDocumentDetail,
} from "@/api/fiscal";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { useUiLocale } from "@/i18n/use-ui-locale";

import { ghostButtonClass, hintStyle, Icon, primaryButtonStyle } from "./fiscal-ui";

/** The document as the customer receives it (ADR-245), in its own language or another, with its PDF. */
export function DocumentViewDialog({ token, document, onClose }: { token: string; document: FiscalDocumentDetail; onClose: () => void }) {
  const t = useTranslations("FiscalDocuments");
  const locale = useUiLocale();
  const own = (DOCUMENT_LANGUAGES as readonly string[]).includes(document.language) ? (document.language as DocumentLanguage) : "en";
  const [language, setLanguage] = useState<DocumentLanguage>(own);
  const html = useQuery({
    queryKey: ["admin", "fiscal", "document-html", document.id, language],
    enabled: Boolean(token),
    queryFn: () => fetchDocumentHtml(token, document.id, language === own ? undefined : language),
  });
  const pdf = useMutation({
    mutationFn: () => fetchDocumentPdf(token, document.id, language === own ? undefined : language),
    onSuccess: (blob) => saveBlob(blob, `${document.number}${language === own ? "" : `-${language}`}.pdf`),
  });
  const names = new Intl.DisplayNames([locale], { type: "language" });

  return (
    <Dialog
      variant="screen"
      size="3xl"
      title={<span className="font-mono">{document.number}</span>}
      ariaLabel={t("documentTitle", { number: document.number })}
      onClose={onClose}
      testId="fiscal-document-view"
      error={pdf.isError ? t("pdfFailed") : null}
      footerStart={
        <label className="flex items-center gap-2 text-xs" style={hintStyle}>
          {t("language")}
          <Select
            data-testid="fiscal-view-language"
            aria-label={t("language")}
            value={language}
            onValueChange={(value) => setLanguage(value as DocumentLanguage)}
            className="min-h-9 rounded-xl px-3 text-sm"
            style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {DOCUMENT_LANGUAGES.map((code) => (
              <option key={code} value={code}>{names.of(code) ?? code}</option>
            ))}
          </Select>
        </label>
      }
      footer={
        <button type="button" className={ghostButtonClass} style={primaryButtonStyle} onClick={() => pdf.mutate()} disabled={pdf.isPending} data-testid="fiscal-view-pdf">
          <Icon name="download" size={15} />
          {t("downloadPdf")}
        </button>
      }
    >
      {html.isPending ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : html.isError ? (
        <ErrorNotice>{t("viewFailed")}</ErrorNotice>
      ) : (
        <iframe
          title={t("documentTitle", { number: document.number })}
          srcDoc={html.data}
          sandbox=""
          data-testid="fiscal-view-frame"
          className="h-[70dvh] w-full rounded-xl"
          style={{ background: "var(--paper)", border: "1px solid var(--border)" }}
        />
      )}
    </Dialog>
  );
}
