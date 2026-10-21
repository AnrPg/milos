"use client";

import { useId, useState, type ReactNode } from "react";
import { useTranslations } from "next-intl";

/**
 * A button that asks on the page before it acts: tap once to see what will
 * happen, then confirm or keep things as they are. No browser dialog.
 */
export function ConfirmButton({
  label,
  question,
  confirmLabel,
  onConfirm,
  pending = false,
  disabled = false,
  testId,
}: {
  label: string;
  question: ReactNode;
  confirmLabel: string;
  onConfirm: () => void;
  pending?: boolean;
  disabled?: boolean;
  testId?: string;
}) {
  const t = useTranslations("CheckIn");
  const [asking, setAsking] = useState(false);
  const id = useId();
  const base = "min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-50";

  if (!asking) {
    return (
      <button
        type="button"
        className={base}
        disabled={disabled || pending}
        onClick={() => setAsking(true)}
        style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        data-testid={testId}
      >
        {label}
      </button>
    );
  }

  return (
    <div role="group" aria-labelledby={id} className="flex flex-col gap-2 rounded-2xl p-3" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}>
      <p id={id} className="text-sm" style={{ color: "var(--text)" }}>{question}</p>
      <div className="flex flex-wrap gap-2">
        <button type="button" className={base} onClick={() => setAsking(false)} style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
          {t("keep")}
        </button>
        <button
          type="button"
          className={base}
          disabled={pending}
          onClick={() => {
            onConfirm();
            setAsking(false);
          }}
          style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}
        >
          {pending ? t("working") : confirmLabel}
        </button>
      </div>
    </div>
  );
}
