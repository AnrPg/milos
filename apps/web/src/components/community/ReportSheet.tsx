"use client";

import { useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { REPORT_REASONS, reportItem, type ReportReason, type ReportTarget } from "@/api/community";
import { clientErrorMessage } from "@/components/client/errors";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";

import { ChoicePill, ErrorLine, Sheet, SheetButton } from "./Sheet";

/**
 * ⋯ › Αναφορά (board 7 Q4): a reason, an optional note, send. The item then
 * disappears for the reporter («Ευχαριστούμε, θα το δει το staff») and staff
 * are told; nothing is hidden from anyone else until staff decide.
 */
export function ReportSheet({
  target,
  targetId,
  onClose,
  onReported,
}: {
  target: ReportTarget;
  targetId: string;
  onClose: () => void;
  onReported: () => void;
}) {
  const t = useTranslations("Clubs");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const [reason, setReason] = useState<ReportReason | null>(null);
  const [note, setNote] = useState("");
  const send = useMutation({
    mutationFn: () =>
      reportItem(tokens!.access_token, {
        target_type: target,
        target_id: targetId,
        reason: reason!,
        note: note.trim() || null,
      }),
  });

  const done = send.isSuccess;
  const close = () => {
    if (done) onReported();
    onClose();
  };

  return (
    <Sheet
      labelId={`report-${targetId}`}
      title={done ? t("reportDoneTitle") : t(`reportTitle_${target}`)}
      onClose={close}
      footer={
        done ? (
          <SheetButton primary onClick={close}>{t("ok")}</SheetButton>
        ) : (
          <>
            <SheetButton onClick={close}>{t("cancel")}</SheetButton>
            <SheetButton primary disabled={!reason || send.isPending} onClick={() => send.mutate()}>
              {send.isPending ? t("sending") : t("reportSend")}
            </SheetButton>
          </>
        )
      }
    >
      {done ? (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("reportDoneBody")}</p>
      ) : (
        <div className="flex flex-col gap-3">
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("reportHint")}</p>
          <div role="radiogroup" aria-label={t("reportReason")} className="grid grid-cols-2 gap-2">
            {REPORT_REASONS.map((option) => (
              <ChoicePill key={option} selected={reason === option} onSelect={() => setReason(option)}>
                {t(`reason_${option}`)}
              </ChoicePill>
            ))}
          </div>
          <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
            {t("reportNote")}
            <textarea
              value={note}
              maxLength={500}
              rows={3}
              onChange={(event) => setNote(event.target.value)}
              placeholder={t("reportNotePlaceholder")}
              className="rounded-2xl px-3 py-2 text-sm font-normal"
              style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
            />
          </label>
          <ErrorLine message={send.error ? clientErrorMessage(send.error, tUi) : null} />
        </div>
      )}
    </Sheet>
  );
}
