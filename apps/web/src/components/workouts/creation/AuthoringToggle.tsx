"use client";

import { useTranslations } from "next-intl";

import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

export type AuthoringKind = "text" | "structured";

type Props = {
  value: AuthoringKind;
  /** Saving before a switch, or no draft yet: the toggle waits. */
  disabled?: boolean;
  busy?: boolean;
  failed?: boolean;
  onChange: (next: AuthoringKind) => void;
};

/**
 * ADR-270: «Ελεύθερο κείμενο / Δομημένο». Free text stays the default way to
 * write a WOD; this quiet switch turns the current workout into a structured
 * plan and back.
 */
export function AuthoringToggle({ value, disabled = false, busy = false, failed = false, onChange }: Props) {
  const t = useTranslations("PlanView.authoring");
  const option = (kind: AuthoringKind, label: string) => {
    const active = value === kind;
    return (
      <button
        type="button"
        aria-pressed={active}
        disabled={disabled || busy}
        onClick={() => {
          if (!active) onChange(kind);
        }}
        className="min-h-8 rounded-lg px-3 text-xs font-bold transition-colors disabled:opacity-50"
        style={active ? { background: "var(--card)", color: "var(--text)", boxShadow: "inset 0 0 0 1px var(--border)" } : { color: "var(--muted)" }}
        data-testid={`authoring-toggle-${kind}`}
      >
        {label}
      </button>
    );
  };
  return (
    <div className="flex flex-wrap items-center justify-end gap-2">
      {failed ? <ErrorNotice variant="text">{t("switchFailed")}</ErrorNotice> : null}
      {busy ? (
        <span className="text-xs" role="status" style={{ color: "var(--muted)" }}>
          {t("switching")}
        </span>
      ) : null}
      <div
        role="group"
        aria-label={t("label")}
        aria-busy={busy}
        className="inline-flex rounded-xl p-0.5"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        data-testid="authoring-toggle"
        data-value={value}
      >
        {option("text", t("freeText"))}
        {option("structured", t("structured"))}
      </div>
    </div>
  );
}

/** Asks before a switch that changes what was written (text kept as a note, or a plan written out as text). */
export function AuthoringSwitchDialog({
  kind,
  busy,
  onConfirm,
  onCancel,
}: {
  kind: "toStructured" | "toText";
  busy: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  const t = useTranslations("PlanView.authoring");
  return (
    <Dialog
      onClose={onCancel}
      title={t(kind === "toStructured" ? "toStructuredTitle" : "toTextTitle")}
      size="sm"
      variant="center"
      dismissible={!busy}
      testId="authoring-switch-dialog"
      footer={
        <>
          <button
            type="button"
            onClick={onCancel}
            disabled={busy}
            className="min-h-10 rounded-xl px-4 text-sm font-bold disabled:opacity-50"
            style={{ color: "var(--text-soft)", border: "1px solid var(--border)" }}
          >
            {t("cancel")}
          </button>
          <button
            type="button"
            onClick={onConfirm}
            disabled={busy}
            className="min-h-10 rounded-xl px-4 text-sm font-black disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            data-testid="authoring-switch-confirm"
          >
            {busy ? t("switching") : t("confirm")}
          </button>
        </>
      }
    >
      <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>
        {t(kind === "toStructured" ? "toStructuredBody" : "toTextBody")}
      </p>
    </Dialog>
  );
}
