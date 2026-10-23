"use client";

import Link from "next/link";
import { useState } from "react";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";

import { ApiError } from "@/api/client";
import { requestPasswordReset, resetPasswordWithRecoveryCode } from "@/api/auth";
import { AuthField } from "@/components/auth/AuthField";
import { AuthNotice, AuthShell, primaryButtonClass, primaryButtonStyle } from "@/components/auth/AuthShell";
import { MIN_PASSWORD_LENGTH, type FieldErrors } from "@/components/auth/auth-errors";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

type View = "request" | "sent" | "code";

const linkClass = "text-sm font-semibold";
const linkStyle = { color: "var(--primary)" } as const;

/**
 * ADR-187: "Forgot password". The request is always answered the same way so
 * it never reveals whether an account exists; people who know the person
 * confirm it is them and email a reset link. A recovery code is the
 * self-service way back in.
 */
export function ForgotPassword() {
  const t = useTranslations("authRecovery");
  const ui = useUiTranslations();
  const router = useRouter();

  const [view, setView] = useState<View>("request");
  const [identifier, setIdentifier] = useState("");
  const [code, setCode] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({});

  function show(next: View) {
    setView(next);
    setError(null);
    setFieldErrors({});
  }

  async function submitRequest() {
    if (identifier.trim().length === 0) {
      setFieldErrors({ identifier: [t("identifierRequired")] });
      return;
    }
    setBusy(true);
    setError(null);
    setFieldErrors({});
    try {
      await requestPasswordReset(identifier.trim());
      setView("sent");
    } catch (caught) {
      setError(localizeError(caught, ui));
    } finally {
      setBusy(false);
    }
  }

  async function submitCode() {
    const errors: FieldErrors = {};
    if (identifier.trim().length === 0) errors.identifier = [t("identifierRequired")];
    if (code.trim().length === 0) errors.code = [t("recoveryCodeRequired")];
    if (password.length < MIN_PASSWORD_LENGTH) errors.password = [t("passwordRule")];
    setFieldErrors(errors);
    setError(null);
    if (Object.keys(errors).length > 0) return;

    setBusy(true);
    try {
      await resetPasswordWithRecoveryCode({ identifier: identifier.trim(), code: code.trim(), password });
      router.replace("/login?reset=done");
    } catch (caught) {
      if (caught instanceof ApiError && caught.payload.code === "invalid_recovery_code") {
        setError(t("recoveryCodeInvalid"));
      } else if (caught instanceof ApiError && caught.payload.code === "weak_password") {
        setFieldErrors({ password: [t("passwordRule")] });
      } else {
        setError(localizeError(caught, ui));
      }
      setBusy(false);
    }
  }

  if (view === "sent") {
    return (
      <AuthShell title={t("requestSentTitle")}>
        <div className="space-y-5 text-center">
          <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }} role="status">
            {t("requestSentBody")}
          </p>
          <Link className={`block ${primaryButtonClass}`} style={primaryButtonStyle} href="/login">
            {t("backToSignIn")}
          </Link>
          <button type="button" className={linkClass} style={linkStyle} onClick={() => show("code")}>
            {t("haveRecoveryCode")}
          </button>
        </div>
      </AuthShell>
    );
  }

  if (view === "code") {
    return (
      <AuthShell title={t("recoveryTitle")}>
        <form
          className="space-y-4"
          noValidate
          onSubmit={(event) => {
            event.preventDefault();
            void submitCode();
          }}
        >
          <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>
            {t("recoveryIntro")}
          </p>
          <AuthField
            label={t("identifierLabel")}
            value={identifier}
            autoComplete="username"
            errors={fieldErrors.identifier}
            onChange={setIdentifier}
          />
          <AuthField
            label={t("recoveryCodeLabel")}
            value={code}
            autoComplete="one-time-code"
            placeholder={t("recoveryCodePlaceholder")}
            errors={fieldErrors.code}
            onChange={setCode}
          />
          <AuthField
            label={t("newPasswordLabel")}
            value={password}
            type="password"
            autoComplete="new-password"
            placeholder={t("passwordRule")}
            errors={fieldErrors.password}
            onChange={setPassword}
          />
          {error ? <AuthNotice>{error}</AuthNotice> : null}
          <button className={primaryButtonClass} style={primaryButtonStyle} disabled={busy} type="submit">
            {busy ? t("saving") : t("setNewPassword")}
          </button>
          <div className="text-center">
            <button type="button" className={linkClass} style={linkStyle} onClick={() => show("request")}>
              {t("askForHelpInstead")}
            </button>
          </div>
        </form>
      </AuthShell>
    );
  }

  return (
    <AuthShell title={t("forgotTitle")}>
      <form
        className="space-y-4"
        noValidate
        onSubmit={(event) => {
          event.preventDefault();
          void submitRequest();
        }}
      >
        <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>
          {t("forgotIntro")}
        </p>
        <AuthField
          label={t("identifierLabel")}
          value={identifier}
          autoComplete="username"
          errors={fieldErrors.identifier}
          onChange={setIdentifier}
        />
        {error ? <AuthNotice>{error}</AuthNotice> : null}
        <button className={primaryButtonClass} style={primaryButtonStyle} disabled={busy} type="submit">
          {busy ? t("sending") : t("sendRequest")}
        </button>
        <div className="flex flex-col items-center gap-3 pt-1">
          <button type="button" className={linkClass} style={linkStyle} onClick={() => show("code")}>
            {t("haveRecoveryCode")}
          </button>
          <Link className={linkClass} style={{ color: "var(--dim)" }} href="/login">
            {t("backToSignIn")}
          </Link>
        </div>
      </form>
    </AuthShell>
  );
}
