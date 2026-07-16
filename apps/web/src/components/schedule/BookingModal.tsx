"use client";


import {useUiTranslations} from "@/i18n/ui";
import { useTranslations } from "next-intl";

type BookingModalProps = {
  title: string;
  description: string;
  busy?: boolean;
  confirmLabel: string;
  inputLabel?: string;
  inputPlaceholder?: string;
  inputValue?: string;
  onInputChange?: (value: string) => void;
  onCancel: () => void;
  onConfirm: () => void;
};

export function BookingModal({
  title,
  description,
  busy = false,
  confirmLabel,
  inputLabel,
  inputPlaceholder,
  inputValue,
  onInputChange,
  onCancel,
  onConfirm,
}: BookingModalProps) {
  const i18n = useUiTranslations();
  const t = useTranslations("Schedule");
  const common = useTranslations("Common");

  return (
    <div className="fixed inset-0 z-40 flex items-center justify-center px-4" style={{ background: "rgba(0,0,0,0.7)" }}>
      <div
        className="w-full max-w-md rounded-[2rem] p-6 shadow-[0_30px_90px_rgba(0,0,0,0.7)]"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        <p className="text-sm font-semibold uppercase tracking-[0.24em] text-[var(--primary)]">{t("confirm")}</p>
        <h3 className="mt-3 text-2xl font-semibold" style={{ color: "var(--text)" }}>{title}</h3>
        <p className="mt-3 text-sm leading-6" style={{ color: "var(--muted)" }}>{description}</p>

        {onInputChange ? (
          <label className="mt-5 block space-y-2 text-sm font-semibold" style={{ color: "var(--muted)" }}>
            <span>{inputLabel ?? t("message")}</span>
            <textarea
              className="min-h-28 w-full rounded-[1.2rem] px-4 py-3 text-sm outline-none"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
              onChange={(event) => onInputChange(event.target.value)}
              placeholder={inputPlaceholder}
              value={inputValue ?? ""}
            />
          </label>
        ) : null}

        <div className="mt-6 flex justify-end gap-3">
          <button
            className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
            style={{ background: "var(--border)", color: "var(--text-soft)" }}
            onClick={onCancel}
            type="button"
          >
            {common("cancel")}
          </button>
          <button
            className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
            style={{ background: "var(--text)", color: "var(--bg)" }}
            disabled={busy}
            onClick={onConfirm}
            type="button"
          >
            {busy ? t("working") : confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
