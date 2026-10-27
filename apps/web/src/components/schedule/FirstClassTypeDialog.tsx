"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";

import { createClassType, type ClassTypeRecord } from "@/api/schedule";
import { Dialog } from "@/components/ui/Dialog";
import { useUiTranslations } from "@/i18n/ui";
import { FieldError } from "@/components/ui/ErrorNotice";
import { fieldBorder, formErrorsFrom, invalidFieldProps, stillApplies, type FormErrors } from "@/lib/form-errors";

/**
 * A gym without any active class type can't hold a class yet (the type is
 * what a class is). Instead of a dead end, staff name the first type here and
 * carry on to the class they were adding. The WOD stays optional (ADR-176).
 */
export function FirstClassTypeDialog({
  token,
  onClose,
  onCreated,
}: {
  token: string;
  onClose: () => void;
  onCreated: (classType: ClassTypeRecord) => void;
}) {
  const t = useTranslations("Schedule");
  const common = useTranslations("Common");
  const i18n = useUiTranslations();
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);
  // ADR-214: the reason sits under the name; anything else inside the dialog.
  const [errors, setErrors] = useState<{ result: FormErrors<"name">; sent: string } | null>(null);
  const trimmed = name.trim();
  const nameError = stillApplies(errors?.result, { name: errors?.sent }, { name: trimmed }).name;

  async function create() {
    if (trimmed.length < 2 || busy) return;
    setBusy(true);
    setErrors(null);
    try {
      onCreated(await createClassType(token, { name: trimmed }));
    } catch (cause) {
      setErrors({ result: formErrorsFrom(cause, i18n, ["name"], { fallback: t("firstClassTypeFailed") }), sent: trimmed });
      setBusy(false);
    }
  }

  return (
    <Dialog
      onClose={onClose}
      title={t("firstClassTypeTitle")}
      size="md"
      error={errors?.result.message}
      footer={
        <div className="flex gap-3">
          <button
            className="rounded-full px-4 py-2 text-sm font-semibold"
            style={{ background: "var(--border)", color: "var(--text-soft)" }}
            onClick={onClose}
            type="button"
          >
            {common("cancel")}
          </button>
          <button
            className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            disabled={busy || trimmed.length < 2}
            onClick={() => void create()}
            type="button"
          >
            {busy ? common("saving") : t("firstClassTypeCreate")}
          </button>
        </div>
      }
    >
      <form
        className="space-y-4"
        onSubmit={(event) => {
          event.preventDefault();
          void create();
        }}
      >
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>
          {t("firstClassTypeBody")}
        </p>
        <label className="block space-y-2 text-sm font-semibold" style={{ color: "var(--muted)" }}>
          <span>{t("firstClassTypeLabel")}</span>
          <input
            autoFocus
            className="w-full rounded-2xl px-4 py-3 outline-none"
            style={{ background: "var(--panel-muted)", border: fieldBorder(nameError), color: "var(--text)" }}
            {...invalidFieldProps(nameError, "first-class-type-name-error")}
            maxLength={120}
            onChange={(event) => setName(event.target.value)}
            placeholder={t("firstClassTypePlaceholder")}
            value={name}
          />
          <FieldError id="first-class-type-name-error">{nameError}</FieldError>
        </label>
      </form>
    </Dialog>
  );
}
