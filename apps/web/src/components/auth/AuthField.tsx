"use client";

import { useId, type ReactNode } from "react";

import { ErrorNotice } from "@/components/ui/ErrorNotice";

type AuthFieldProps = {
  label: ReactNode;
  value: string;
  onChange: (value: string) => void;
  type?: "text" | "email" | "password";
  autoComplete?: string;
  placeholder?: string;
  /** Shown inside the input before the value (e.g. "@"). */
  prefix?: string;
  /** A quiet line next to the label (availability, counters). */
  status?: ReactNode;
  /** Help under the input, shown while there is no error. */
  hint?: ReactNode;
  errors?: string[];
  maxLength?: number;
  inputMode?: "text" | "email";
  autoFocus?: boolean;
};

// A handle is always Latin: keep it left-to-right and free of autocorrect.
const LATIN_IDENTIFIER_INPUT = { dir: "ltr", autoCapitalize: "none", spellCheck: false } as const;

/** One labelled input of the signed-out forms, styled like the auth console. */
export function AuthField({
  label,
  value,
  onChange,
  type = "text",
  autoComplete,
  placeholder,
  prefix,
  status,
  hint,
  errors = [],
  maxLength,
  inputMode,
  autoFocus,
}: AuthFieldProps) {
  const invalid = errors.length > 0;
  const id = useId();
  const noteId = `${id}-note`;
  const hasNote = invalid || Boolean(hint);

  return (
    <div className="block text-sm font-medium" style={{ color: "var(--text-soft)" }}>
      <span className="flex items-center justify-between gap-3">
        <label htmlFor={id}>{label}</label>
        {status}
      </span>
      <span
        className="mt-2 flex w-full items-center rounded-2xl px-4"
        style={{ background: "var(--bg)", border: `1px solid ${invalid ? "var(--danger)" : "var(--border)"}` }}
      >
        {prefix ? (
          <span aria-hidden="true" className="pe-1" style={{ color: "var(--dim)" }}>
            {prefix}
          </span>
        ) : null}
        <input
          id={id}
          aria-describedby={hasNote ? noteId : undefined}
          className="min-w-0 flex-1 bg-transparent py-3 outline-none"
          style={{ color: "var(--text)" }}
          type={type}
          value={value}
          autoComplete={autoComplete}
          {...(prefix ? LATIN_IDENTIFIER_INPUT : {})}
          placeholder={placeholder}
          maxLength={maxLength}
          inputMode={inputMode}
          autoFocus={autoFocus}
          aria-invalid={invalid}
          onChange={(event) => onChange(event.target.value)}
        />
      </span>
      {invalid ? (
        <ErrorNotice id={noteId} variant="field" className="mt-1.5">
          {errors.join(" ")}
        </ErrorNotice>
      ) : hint ? (
        <span id={noteId} className="mt-1.5 block text-xs font-normal leading-5" style={{ color: "var(--dim)" }}>
          {hint}
        </span>
      ) : null}
    </div>
  );
}
