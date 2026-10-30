"use client";

import { useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { reportPartner, type PartnerReportReason } from "@/api/partners";
import { ChoicePill, ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { FieldError } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";

import { partnerErrorMessage } from "./errors";
import { usePartnersOverview, usePartnersToken } from "./use-partners";

const NOTE_MAX = 500;

/**
 * «Αναφορά» (ADR-280): a reason («Ανήλικος» among them) and an optional note
 * go to the Palee team, never to box staff. Reporting also blocks: the match
 * ends and neither sees the other again. The person isn't told who.
 */
export function PartnerReportSheet({
  targetId,
  name,
  onClose,
  onReported,
}: {
  targetId: string;
  name: string;
  onClose: () => void;
  onReported: () => void;
}) {
  const t = useTranslations("Partners");
  const tUi = useUiTranslations();
  const token = usePartnersToken();
  const overview = usePartnersOverview();
  const reasons = overview.data?.options.report_reasons ?? [];
  const [reason, setReason] = useState<PartnerReportReason | null>(null);
  const [note, setNote] = useState("");
  const [tried, setTried] = useState(false);
  const send = useMutation({
    mutationFn: () => reportPartner(token!, { target_id: targetId, reason: reason!, note: note.trim() || null }),
  });
  const done = send.isSuccess;
  const close = () => {
    if (done) onReported();
    onClose();
  };
  const submit = () => {
    setTried(true);
    if (reason) send.mutate();
  };

  return (
    <Sheet
      labelId={`partner-report-${targetId}`}
      title={done ? t("reportDoneTitle") : t("reportTitle", { name })}
      onClose={close}
      footer={
        done ? (
          <SheetButton primary onClick={close}>{t("ok")}</SheetButton>
        ) : (
          <>
            <SheetButton onClick={close}>{t("cancel")}</SheetButton>
            <SheetButton primary disabled={send.isPending} onClick={submit}>
              {send.isPending ? t("sending") : t("reportSend")}
            </SheetButton>
          </>
        )
      }
    >
      {done ? (
        <p className="text-sm" style={{ color: "var(--text-soft)" }} data-testid="partner-report-done">{t("reportDoneBody")}</p>
      ) : (
        <form
          className="flex flex-col gap-3"
          noValidate
          onSubmit={(event) => {
            event.preventDefault();
            submit();
          }}
          data-testid="partner-report"
        >
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("reportHint")}</p>
          {overview.isPending ? <p className="text-sm" role="status" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}
          <div className="flex flex-col gap-1">
            <div role="radiogroup" aria-label={t("reportReason")} className="grid grid-cols-1 gap-2 sm:grid-cols-2">
              {reasons.map((option) => (
                <ChoicePill key={option} selected={reason === option} onSelect={() => setReason(option)}>
                  {t(`reportReason_${option}`)}
                </ChoicePill>
              ))}
            </div>
            <FieldError id="partner-report-reason-error">{tried && !reason ? t("reportReasonRequired") : null}</FieldError>
          </div>
          <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
            {t("reportNote")}
            <textarea
              value={note}
              maxLength={NOTE_MAX}
              rows={3}
              onChange={(event) => setNote(event.target.value)}
              placeholder={t("reportNotePlaceholder")}
              className="resize-none rounded-2xl px-3 py-2 text-sm font-normal"
              style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
            />
          </label>
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t("reportAlsoBlocks")}</p>
          <ErrorLine message={partnerErrorMessage(send.error ?? overview.error, t, tUi)} />
        </form>
      )}
    </Sheet>
  );
}
