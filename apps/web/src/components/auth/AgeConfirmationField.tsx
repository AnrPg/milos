"use client";

import Link from "next/link";
import { useId } from "react";
import { useTranslations } from "next-intl";

import { ErrorNotice } from "@/components/ui/ErrorNotice";

/** ADR-267: the minimum age to sign up (mirrors `Identity.Domain.AgePolicy`). */
export const MINIMUM_AGE = 16;

type AgeConfirmationFieldProps = {
  checked: boolean;
  onChange: (checked: boolean) => void;
  errors?: string[];
};

/**
 * ADR-267: the one sign-up question about age. Palee asks only whether the
 * person is at least 16, never a date of birth; the API refuses a sign-up
 * without it (422 `errors.age_confirmed`), and the error shows under the box
 * (ADR-214).
 */
export function AgeConfirmationField({ checked, onChange, errors = [] }: AgeConfirmationFieldProps) {
  const t = useTranslations("legal");
  const id = useId();
  const noteId = `${id}-note`;
  const invalid = errors.length > 0;

  return (
    <div className="text-sm" style={{ color: "var(--text-soft)" }}>
      <span className="flex items-start gap-3">
        <input
          id={id}
          type="checkbox"
          className="mt-0.5 h-5 w-5 shrink-0"
          style={{ accentColor: "var(--primary)" }}
          checked={checked}
          aria-invalid={invalid}
          aria-describedby={invalid ? noteId : undefined}
          onChange={(event) => onChange(event.target.checked)}
        />
        <span className="leading-5">
          <label htmlFor={id} className="font-medium" style={{ color: "var(--text)" }}>
            {t("ageConfirmation", { age: MINIMUM_AGE })}
          </label>
          <span className="mt-1 block text-xs leading-5" style={{ color: "var(--dim)" }}>
            {t.rich("signUpAgreement", {
              terms: (chunks) => (
                <Link href="/terms" target="_blank" className="font-semibold underline" style={{ color: "var(--primary)" }}>
                  {chunks}
                </Link>
              ),
              privacy: (chunks) => (
                <Link href="/privacy" target="_blank" className="font-semibold underline" style={{ color: "var(--primary)" }}>
                  {chunks}
                </Link>
              ),
            })}
          </span>
        </span>
      </span>
      {invalid ? (
        <ErrorNotice id={noteId} variant="field" className="mt-1.5">
          {errors.join(" ")}
        </ErrorNotice>
      ) : null}
    </div>
  );
}
