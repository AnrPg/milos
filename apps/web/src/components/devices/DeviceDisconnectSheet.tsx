"use client";

import { useId, useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { ConfirmButton } from "@/components/check-in/ConfirmButton";
import { ChoicePill, ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { deviceErrorKey } from "@/components/devices/DeviceBits";

export type DisconnectCopy = {
  eyebrow: string;
  title: string;
  deleteLabel: string;
  deleteHint: string;
  confirmKeep: string;
  confirmDelete: string;
};

/**
 * «Αποσύνδεση» for any device (board 16 Q6 A, ADR-172): keep what came in,
 * or delete everything that came from it; the page asks once more before it
 * acts.
 */
export function DeviceDisconnectSheet<T>({
  copy,
  disconnect,
  onClose,
  onDone,
  testId,
  confirmTestId,
}: {
  copy: DisconnectCopy;
  disconnect: (deleteData: boolean) => Promise<T>;
  onClose: () => void;
  onDone: (result: T, deleted: boolean) => void;
  testId: string;
  confirmTestId: string;
}) {
  const t = useTranslations("Devices");
  const labelId = useId();
  const choiceId = useId();
  const [deleteData, setDeleteData] = useState(false);
  const mutation = useMutation({
    mutationFn: () => disconnect(deleteData),
    onSuccess: (result) => onDone(result, deleteData),
  });

  return (
    <Sheet title={copy.title} eyebrow={copy.eyebrow} labelId={labelId} onClose={onClose} footer={<SheetButton onClick={onClose}>{t("cancel")}</SheetButton>}>
      <div className="flex flex-col gap-4" data-testid={testId}>
        <div role="radiogroup" aria-labelledby={choiceId} className="flex flex-col gap-2">
          <span id={choiceId} className="sr-only">{copy.title}</span>
          <ChoicePill selected={!deleteData} onSelect={() => setDeleteData(false)} hint={t("disconnectKeepHint")}>
            {t("disconnectKeep")}
          </ChoicePill>
          <ChoicePill selected={deleteData} onSelect={() => setDeleteData(true)} hint={copy.deleteHint}>
            {copy.deleteLabel}
          </ChoicePill>
        </div>
        <ConfirmButton
          label={t("disconnect")}
          question={deleteData ? copy.confirmDelete : copy.confirmKeep}
          confirmLabel={t("disconnectAction")}
          pending={mutation.isPending}
          onConfirm={() => mutation.mutate()}
          testId={confirmTestId}
        />
        <ErrorLine message={mutation.isError ? t(deviceErrorKey(mutation.error)) : null} />
      </div>
    </Sheet>
  );
}
