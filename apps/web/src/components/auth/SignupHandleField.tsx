"use client";

import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import { checkHandleAvailable, suggestHandle } from "@/api/auth";
import { AuthField } from "@/components/auth/AuthField";
import { handleInput } from "@/components/auth/auth-errors";

const DEBOUNCE_MS = 400;
const MIN_HANDLE_LENGTH = 3;

type Availability =
  | { state: "idle" }
  | { state: "checking" }
  | { state: "available"; handle: string }
  | { state: "taken"; suggestion: string | null }
  | { state: "invalid" };

/**
 * ADR-187: while the person has not typed a handle of their own, keep it in
 * step with the display name (the server suggests a free Latin form).
 */
export function useHandleSuggestion(displayName: string, enabled: boolean, onSuggest: (handle: string) => void) {
  useEffect(() => {
    const name = displayName.trim();
    if (!enabled || name.length === 0) return;

    const controller = new AbortController();
    const timer = setTimeout(() => {
      suggestHandle(name, controller.signal)
        .then(({ handle }) => {
          if (handle) onSuggest(handle);
        })
        .catch(() => {
          // A missing suggestion only means the person types a handle themselves.
        });
    }, DEBOUNCE_MS);

    return () => {
      clearTimeout(timer);
      controller.abort();
    };
  }, [displayName, enabled, onSuggest]);
}

type SignupHandleFieldProps = {
  value: string;
  onChange: (value: string) => void;
  errors?: string[];
};

/** The @handle input of sign-up, with a quiet live free/taken hint. */
export function SignupHandleField({ value, onChange, errors }: SignupHandleFieldProps) {
  const t = useTranslations("authRecovery");
  const [availability, setAvailability] = useState<Availability>({ state: "idle" });

  useEffect(() => {
    const handle = value.trim();
    if (handle.length < MIN_HANDLE_LENGTH) {
      queueMicrotask(() => setAvailability({ state: "idle" }));
      return;
    }

    queueMicrotask(() => setAvailability({ state: "checking" }));
    const controller = new AbortController();
    const timer = setTimeout(() => {
      checkHandleAvailable(handle, controller.signal)
        .then((result) =>
          setAvailability(
            result.available
              ? { state: "available", handle: result.handle }
              : { state: "taken", suggestion: result.suggestions[0] ?? null },
          ),
        )
        .catch((caught) => {
          if (controller.signal.aborted) return;
          setAvailability(caught instanceof ApiError && caught.status === 400 ? { state: "invalid" } : { state: "idle" });
        });
    }, DEBOUNCE_MS);

    return () => {
      clearTimeout(timer);
      controller.abort();
    };
  }, [value]);

  const status =
    availability.state === "checking" ? (
      <span className="text-xs font-normal" style={{ color: "var(--dim)" }}>
        {t("handleChecking")}
      </span>
    ) : availability.state === "available" ? (
      <span className="text-xs font-semibold" style={{ color: "var(--success)" }} aria-live="polite">
        {t("handleAvailable", { handle: availability.handle })}
      </span>
    ) : availability.state === "taken" ? (
      <span className="text-xs font-semibold" style={{ color: "var(--danger-strong)" }} aria-live="polite">
        {t("handleTaken")}
      </span>
    ) : null;

  const hint =
    availability.state === "taken" && availability.suggestion ? (
      <button
        type="button"
        className="font-semibold"
        style={{ color: "var(--primary)" }}
        onClick={() => onChange(availability.suggestion ?? value)}
      >
        {t("handleTryInstead", { handle: availability.suggestion })}
      </button>
    ) : availability.state === "invalid" ? (
      <span className="font-semibold" style={{ color: "var(--danger-strong)" }}>{t("handleRule")}</span>
    ) : (
      t("handleHint")
    );

  return (
    <AuthField
      label={t("handleLabel")}
      value={value}
      prefix="@"
      autoComplete="username"
      maxLength={40}
      status={status}
      hint={hint}
      errors={errors}
      onChange={(next) => onChange(handleInput(next))}
    />
  );
}
