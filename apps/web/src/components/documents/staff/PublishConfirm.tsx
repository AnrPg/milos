"use client";

import { useId } from "react";
import { useTranslations } from "next-intl";

import { primaryButtonClass, primaryButtonStyle } from "@/components/staff/staff-ui";

/**
 * The confirm step before a mandatory document starts blocking bookings
 * (product owner, 2026-10-29): it says how many clients could not book right
 * now. Without `onConfirm` the confirm button submits the surrounding form.
 */
export function PublishConfirm({
  count,
  confirmLabel,
  busyLabel,
  busy = false,
  onBack,
  onConfirm,
}: {
  /** Clients blocked at once; null while the count is loading. */
  count: number | null;
  confirmLabel: string;
  /** What the confirm button says while it works; «Δημοσίευση…» by default. */
  busyLabel?: string;
  busy?: boolean;
  onBack: () => void;
  onConfirm?: () => void;
}) {
  const t = useTranslations("Documents");
  const titleId = useId();
  return (
    <div
      role="alertdialog"
      aria-labelledby={titleId}
      data-testid="publish-confirm"
      className="flex w-full flex-col gap-2 rounded-2xl px-4 py-3"
      style={{
        background: "color-mix(in srgb, var(--warning) 12%, var(--panel))",
        border: "1px solid color-mix(in srgb, var(--warning) 45%, transparent)",
      }}
    >
      <b id={titleId} className="text-sm" style={{ color: "var(--text)" }}>
        <span aria-hidden="true">🔒 </span>
        {t("confirmBlockTitle")}
      </b>
      <p className="text-sm leading-5" style={{ color: "var(--text-soft)" }}>
        {count === null ? t("confirmBlockUnknown") : t("confirmBlockCount", { count })}
      </p>
      <div className="flex flex-wrap items-center justify-end gap-2">
        <button type="button" onClick={onBack} disabled={busy} className="min-h-10 rounded-full px-4 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
          {t("confirmBack")}
        </button>
        <button type={onConfirm ? "button" : "submit"} onClick={onConfirm} disabled={busy} className={primaryButtonClass} style={primaryButtonStyle}>
          {busy ? (busyLabel ?? t("publishing")) : confirmLabel}
        </button>
      </div>
    </div>
  );
}
