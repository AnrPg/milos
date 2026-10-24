"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { useTranslations } from "next-intl";

import { completePasswordReset } from "@/api/auth";
import { AuthField } from "@/components/auth/AuthField";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { AuthNotice, AuthShell, primaryButtonClass, primaryButtonStyle } from "@/components/auth/AuthShell";
import {
  passwordLongEnough,
  resetFailure,
  resetTokenFromHash,
  type FieldErrors,
  type ResetFailure,
} from "@/components/auth/auth-errors";
import { useSession } from "@/components/session-provider";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

type LinkState = "reading" | "ready" | "missing";

/**
 * ADR-187: the page a one-time reset link opens (`/reset-password#token=...`).
 * Setting the password signs every device out.
 */
export function ResetPassword() {
  const t = useTranslations("authRecovery");
  const ui = useUiTranslations();
  const { status, signOut } = useSession();

  const [token, setToken] = useState<string | null>(null);
  const [linkState, setLinkState] = useState<LinkState>("reading");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  const [failure, setFailure] = useState<ResetFailure | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({});

  // The fragment only exists in the browser.
  useEffect(() => {
    const found = resetTokenFromHash(window.location.hash);
    queueMicrotask(() => {
      setToken(found);
      setLinkState(found ? "ready" : "missing");
    });
  }, []);

  // Every session ended with the reset, this one included.
  const signedOutRef = useRef(false);
  useEffect(() => {
    if (!done || status !== "authenticated" || signedOutRef.current) return;
    signedOutRef.current = true;
    signOut();
  }, [done, signOut, status]);

  async function submit() {
    if (!token) return;
    const errors: FieldErrors = {};
    if (!passwordLongEnough(password)) errors.password = [t("passwordRule")];
    else if (confirm !== password) errors.confirm = [t("passwordsDontMatch")];
    setFieldErrors(errors);
    setError(null);
    if (Object.keys(errors).length > 0) return;

    setBusy(true);
    try {
      await completePasswordReset(token, password);
      setDone(true);
    } catch (caught) {
      const kind = resetFailure(caught);
      if (kind === "weak_password") setFieldErrors({ password: [t("passwordRule")] });
      else if (kind === "other") setError(localizeError(caught, ui));
      else setFailure(kind);
    } finally {
      setBusy(false);
    }
  }

  if (done) {
    return (
      <AuthShell title={t("resetDoneTitle")}>
        <div className="space-y-5 text-center">
          <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }} role="status">
            {t("resetDoneBody")}
          </p>
          <Link className={`block ${primaryButtonClass}`} style={primaryButtonStyle} href="/login">
            {t("signIn")}
          </Link>
        </div>
      </AuthShell>
    );
  }

  if (linkState === "missing" || failure) {
    return (
      <AuthShell title={t("resetLinkProblemTitle")}>
        <div className="space-y-5 text-center">
          <ErrorNotice className="text-start">
            {failure === "expired" ? t("resetLinkExpired") : t("resetLinkInvalid")}
          </ErrorNotice>
          <Link className={`block ${primaryButtonClass}`} style={primaryButtonStyle} href="/forgot-password">
            {t("askForNewLink")}
          </Link>
          <Link className="text-sm font-semibold" style={{ color: "var(--dim)" }} href="/login">
            {t("backToSignIn")}
          </Link>
        </div>
      </AuthShell>
    );
  }

  return (
    <AuthShell title={t("resetTitle")}>
      <form
        className="space-y-4"
        noValidate
        onSubmit={(event) => {
          event.preventDefault();
          void submit();
        }}
      >
        <AuthField
          label={t("newPasswordLabel")}
          value={password}
          type="password"
          autoComplete="new-password"
          placeholder={t("passwordRule")}
          errors={fieldErrors.password}
          onChange={setPassword}
        />
        <AuthField
          label={t("confirmPasswordLabel")}
          value={confirm}
          type="password"
          autoComplete="new-password"
          errors={fieldErrors.confirm}
          onChange={setConfirm}
        />
        {error ? <AuthNotice>{error}</AuthNotice> : null}
        <button
          className={primaryButtonClass}
          style={primaryButtonStyle}
          disabled={busy || linkState !== "ready"}
          type="submit"
        >
          {busy ? t("saving") : t("setNewPassword")}
        </button>
      </form>
    </AuthShell>
  );
}
