"use client";

import { useLocale } from "next-intl";
import { useState } from "react";

import { useUiTranslations } from "@/i18n/ui";

/**
 * Shown when ending a membership hits the package's minimum commitment
 * (ADR-097). The admin may still proceed, but has to give a reason.
 */
export function CommitmentOverridePrompt({
  endsOn,
  pending,
  onConfirm,
  onCancel,
}: {
  endsOn: string | null;
  pending: boolean;
  onConfirm: (reason: string) => void;
  onCancel: () => void;
}) {
  const i18n = useUiTranslations();
  const locale = useLocale();
  const [reason, setReason] = useState("");
  const date = endsOn
    ? new Intl.DateTimeFormat(locale, { dateStyle: "medium", timeZone: "UTC" }).format(new Date(Date.parse(endsOn)))
    : null;

  return (
    <div
      className="space-y-3 rounded-2xl p-4 text-sm"
      role="alert"
      style={{ background: "color-mix(in srgb, var(--warning) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--warning) 30%, transparent)" }}
    >
      <p className="font-semibold" style={{ color: "var(--text)" }}>
        {date ? i18n("admCommitmentActiveUntil", { date }) : i18n("admCommitmentActive")}
      </p>
      <p style={{ color: "var(--muted)" }}>{i18n("admCommitmentOverrideHint")}</p>
      <textarea
        aria-label={i18n("admCommitmentOverrideReason")}
        className="min-h-16 w-full rounded-xl px-3 py-2"
        onChange={(event) => setReason(event.target.value)}
        placeholder={i18n("admCommitmentOverrideReason")}
        style={{ background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)" }}
        value={reason}
      />
      <div className="flex flex-wrap gap-2">
        <button
          className="rounded-full px-4 py-2 text-xs font-semibold disabled:opacity-50"
          disabled={pending || reason.trim().length < 3}
          onClick={() => onConfirm(reason.trim())}
          style={{ background: "var(--danger)", color: "white" }}
          type="button"
        >
          {i18n("admCommitmentEndAnyway")}
        </button>
        <button
          className="rounded-full px-4 py-2 text-xs font-semibold"
          onClick={onCancel}
          style={{ background: "var(--border)", color: "var(--text-soft)" }}
          type="button"
        >
          {i18n("admCommitmentKeep")}
        </button>
      </div>
    </div>
  );
}
