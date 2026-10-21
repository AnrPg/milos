"use client";

import { useMutation } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { exportDeviceData } from "@/api/phone-health";

/**
 * «Λήψη δεδομένων συσκευών» (plan D11, ADR-172): everything connected devices
 * brought in, as one JSON file. Nights and weigh-ins are in the Ευεξία and
 * Σώμα exports, where they live. One quiet link under the devices.
 */
export function DeviceDataExport({ token }: { token: string }) {
  const t = useTranslations("Devices");
  const download = useMutation({
    mutationFn: () => exportDeviceData(token),
    onSuccess: (data) => {
      const url = URL.createObjectURL(new Blob([JSON.stringify(data, null, 2)], { type: "application/json" }));
      const link = document.createElement("a");
      link.href = url;
      link.download = `milos-devices-${new Date().toISOString().slice(0, 10)}.json`;
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.setTimeout(() => URL.revokeObjectURL(url), 1_000);
    },
  });
  return (
    <div className="flex flex-col gap-1">
      <button
        type="button"
        disabled={download.isPending}
        onClick={() => download.mutate()}
        className="min-h-11 self-start text-sm font-bold underline-offset-4 hover:underline disabled:opacity-50"
        style={{ color: "var(--primary)" }}
        data-testid="device-data-export"
      >
        {t("exportData")}
      </button>
      {download.isError ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{t("exportFailed")}</p> : null}
    </div>
  );
}
