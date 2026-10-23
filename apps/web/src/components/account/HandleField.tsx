"use client";

import { useEffect, useId, useState } from "react";
import { useTranslations } from "next-intl";

import { checkHandleAvailable, type HandleAvailability } from "@/api/auth";
import { cleanHandleInput, looksLikeHandle } from "@/components/account/account-model";

type Status =
  | { state: "idle" }
  | { state: "checking" }
  | { state: "invalid" }
  | { state: "result"; result: HandleAvailability };

type Checked = { handle: string; result: HandleAvailability | "invalid" };

/**
 * ADR-187: an @handle input that checks availability as you type (Latin
 * a–z 0–9 . _; the server folds other scripts) and offers free alternatives.
 * `unchangedHandle` is the person's own current handle, never reported taken.
 */
export function HandleField({
  value,
  onChange,
  unchangedHandle,
  disabled,
  hint,
}: {
  value: string;
  onChange: (value: string) => void;
  unchangedHandle?: string | null;
  disabled?: boolean;
  hint?: string;
}) {
  const t = useTranslations("accountProfiles");
  const inputId = useId();
  const [checked, setChecked] = useState<Checked | null>(null);
  const handle = cleanHandleInput(value);
  const unchanged = Boolean(unchangedHandle) && handle === unchangedHandle;
  const wellFormed = looksLikeHandle(handle);
  const shouldCheck = Boolean(handle) && !unchanged && wellFormed;

  useEffect(() => {
    if (!shouldCheck) return;
    const controller = new AbortController();
    const timer = window.setTimeout(() => {
      checkHandleAvailable(handle, controller.signal)
        .then((result) => setChecked({ handle, result }))
        .catch(() => {
          if (!controller.signal.aborted) setChecked({ handle, result: "invalid" });
        });
    }, 350);
    return () => {
      window.clearTimeout(timer);
      controller.abort();
    };
  }, [handle, shouldCheck]);

  const current = checked?.handle === handle ? checked.result : null;
  const status: Status = !handle || unchanged
    ? { state: "idle" }
    : !wellFormed || current === "invalid"
      ? { state: "invalid" }
      : current
        ? { state: "result", result: current }
        : { state: "checking" };

  const folded =
    status.state === "result" && status.result.handle !== handle ? status.result.handle : null;

  return (
    <div className="space-y-1.5">
      <label
        htmlFor={inputId}
        className="block text-xs font-semibold uppercase tracking-[0.18em]"
        style={{ color: "var(--muted)" }}
      >
        {t("handleLabel")}
      </label>
      <div
        className="flex items-center rounded-xl px-4"
        style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
        dir="ltr"
      >
        <span aria-hidden="true" className="text-sm" style={{ color: "var(--dim)" }}>@</span>
        <input
          id={inputId}
          value={value}
          onChange={(event) => onChange(event.target.value)}
          disabled={disabled}
          autoCapitalize="none"
          autoCorrect="off"
          autoComplete="username"
          spellCheck={false}
          maxLength={31}
          className="w-full bg-transparent py-2.5 ps-1 text-sm outline-none"
          style={{ color: "var(--text)" }}
        />
      </div>
      <div aria-live="polite" className="min-h-[1rem] text-xs">
        {status.state === "checking" ? (
          <span style={{ color: "var(--dim)" }}>{t("handleChecking")}</span>
        ) : status.state === "invalid" ? (
          <span style={{ color: "var(--danger)" }}>{t("handleRules")}</span>
        ) : status.state === "result" && status.result.available ? (
          <span style={{ color: "var(--success)" }}>
            {folded ? t("handleAvailableAs", { handle: folded }) : t("handleAvailable")}
          </span>
        ) : status.state === "result" ? (
          <span className="flex flex-wrap items-center gap-1.5">
            <span style={{ color: "var(--danger)" }}>{t("handleTaken")}</span>
            {status.result.suggestions.map((suggestion) => (
              <button
                key={suggestion}
                type="button"
                onClick={() => onChange(suggestion)}
                className="rounded-full px-2 py-0.5 font-semibold"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
                dir="ltr"
              >
                @{suggestion}
              </button>
            ))}
          </span>
        ) : hint ? (
          <span style={{ color: "var(--dim)" }}>{hint}</span>
        ) : null}
      </div>
    </div>
  );
}
