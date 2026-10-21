"use client";

import { useTranslations } from "next-intl";

import { disconnectGarmin, type GarminDisconnectResponse } from "@/api/devices";
import { DeviceDisconnectSheet } from "@/components/devices/DeviceDisconnectSheet";

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
  return (
    <DeviceDisconnectSheet
      copy={{
        eyebrow: t("garminName"),
        title: t("disconnectTitle"),
        deleteLabel: t("disconnectDelete"),
        deleteHint: t("disconnectDeleteHint"),
        confirmKeep: t("disconnectConfirmKeep"),
        confirmDelete: t("disconnectConfirmDelete"),
      }}
      disconnect={(deleteData) => disconnectGarmin(token, deleteData)}
      onClose={onClose}
      onDone={onDone}
      testId="garmin-disconnect-sheet"
      confirmTestId="garmin-disconnect-confirm"
    />
  );
}
