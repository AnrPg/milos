"use client";

import { useId, useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { disconnectGarmin, type GarminDisconnectResponse } from "@/api/devices";
import { ConfirmButton } from "@/components/check-in/ConfirmButton";
import { ChoicePill, ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { deviceErrorKey } from "@/components/devices/DeviceBits";

/**
 * «Αποσύνδεση» (board 16 Q6 A): keep what came in, or delete everything that
 * came from Garmin; the page asks once more before it acts.
 */
export function GarminDisconnectSheet({
  token,
  onClose,
  onDone,
}: {
  token: string;
  onClose: () => void;
  onDone: (result: GarminDisconnectResponse, deleted: boolean) => void;
}) {
  const t = useTranslations("Devices");
  const labelId = useId();
  const choiceId = useId();
  const [deleteData, setDeleteData] = useState(false);
  const disconnect = useMutation({
    mutationFn: () => disconnectGarmin(token, deleteData),
    onSuccess: (result) => onDone(result, deleteData),
  });

  return (
    <Sheet
      title={t("disconnectTitle")}
      eyebrow={t("garminName")}
      labelId={labelId}
      onClose={onClose}
      footer={<SheetButton onClick={onClose}>{t("cancel")}</SheetButton>}
    >
      <div className="flex flex-col gap-4" data-testid="garmin-disconnect-sheet">
        <div role="radiogroup" aria-labelledby={choiceId} className="flex flex-col gap-2">
          <span id={choiceId} className="sr-only">{t("disconnectTitle")}</span>
          <ChoicePill selected={!deleteData} onSelect={() => setDeleteData(false)} hint={t("disconnectKeepHint")}>
            {t("disconnectKeep")}
          </ChoicePill>
          <ChoicePill selected={deleteData} onSelect={() => setDeleteData(true)} hint={t("disconnectDeleteHint")}>
            {t("disconnectDelete")}
          </ChoicePill>
        </div>
        <ConfirmButton
          label={t("disconnect")}
          question={deleteData ? t("disconnectConfirmDelete") : t("disconnectConfirmKeep")}
          confirmLabel={t("disconnectAction")}
          pending={disconnect.isPending}
          onConfirm={() => disconnect.mutate()}
          testId="garmin-disconnect-confirm"
        />
        <ErrorLine message={disconnect.isError ? t(deviceErrorKey(disconnect.error)) : null} />
      </div>
    </Sheet>
  );
}
