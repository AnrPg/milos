"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { useTranslations } from "next-intl";

import { completePasswordReset, inspectPasswordReset } from "@/api/auth";
import { AuthField } from "@/components/auth/AuthField";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { AuthNotice, AuthShell, primaryButtonClass, primaryButtonStyle } from "@/components/auth/AuthShell";
import {
  passwordLongEnough,
  resetFailure,
  resetTokenFromLocation,
  type FieldErrors,
  type ResetFailure,
} from "@/components/auth/auth-errors";
import { useSession } from "@/components/session-provider";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

type LinkState = "reading" | "ready" | "missing";

/**
 * ADR-187, ADR-206: the page a one-time reset link opens
 * (`/reset-password#token=...`; older handler links used `?token=`). Opening
 * the page only checks the link; it is spent when the new password is saved,
 * which signs every device out.
 */
export function ResetPassword() {
  const t = useTranslations("authRecovery");
  const pr = useTranslations("passwordReset");
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

  // The fragment only exists in the browser. The token is kept in memory and
  // taken out of the address bar, so it stays out of history and referrers.
  useEffect(() => {
    let cancelled = false;
    const found = resetTokenFromLocation(window.location.hash, window.location.search);
    if (found) window.history.replaceState(window.history.state, "", window.location.pathname);
    queueMicrotask(() => {
      if (cancelled) return;
      setToken(found);
      if (!found) setLinkState("missing");
    });
    if (found) {
      inspectPasswordReset(found)
        .then(() => {
          if (!cancelled) setLinkState("ready");
        })
        .catch((caught: unknown) => {
          if (cancelled) return;
          const kind = resetFailure(caught);
          // Offline or a server hiccup: let the person try; submitting tells.
          if (kind === "other" || kind === "weak_password") setLinkState("ready");
          else setFailure(kind);
        });
    }
    return () => {
      cancelled = true;
    };
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
    const problem =
      failure === "expired" ? pr("linkExpired") : failure === "used" ? pr("linkUsed") : pr("linkInvalid");
    return (
      <AuthShell title={failure === "used" ? pr("linkUsedTitle") : t("resetLinkProblemTitle")}>
        <div className="space-y-5 text-center">
          <ErrorNotice className="text-start">{problem}</ErrorNotice>
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

  if (linkState === "reading") {
    return (
      <AuthShell title={t("resetTitle")}>
        <p className="text-center text-sm" style={{ color: "var(--dim)" }} role="status">
          {pr("checkingLink")}
        </p>
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
