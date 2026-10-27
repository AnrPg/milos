"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { useTranslations } from "next-intl";

import { signOutEverywhereWithLink } from "@/api/auth";
import { AuthNotice, AuthShell, primaryButtonClass, primaryButtonStyle } from "@/components/auth/AuthShell";
import { resetTokenFromHash } from "@/components/auth/auth-errors";
import { signOutLinkFailure, type SignOutLinkFailure } from "@/components/auth/sign-out-link";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

type LinkState = "reading" | "ready" | "missing";

/**
 * ADR-208: the page a security notice's "sign out everywhere" link opens
 * (`/sign-out-everywhere#token=...`). One tap ends every session of the
 * account, this one included; then the person chooses a new password.
 * The token stays in the fragment, so it never reaches a server log, and
 * nothing happens until the tap (a mail scanner opening the link does nothing).
 */
export function SignOutEverywhere() {
  const t = useTranslations("securityNotices");
  const ui = useUiTranslations();
  const { status, signOut } = useSession();

  const [token, setToken] = useState<string | null>(null);
  const [linkState, setLinkState] = useState<LinkState>("reading");
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  const [failure, setFailure] = useState<Exclude<SignOutLinkFailure, "other"> | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const found = resetTokenFromHash(window.location.hash);
    queueMicrotask(() => {
      setToken(found);
      setLinkState(found ? "ready" : "missing");
    });
  }, []);

  // This browser's session ended too.
  const signedOutRef = useRef(false);
  useEffect(() => {
    if (!done || status !== "authenticated" || signedOutRef.current) return;
    signedOutRef.current = true;
    signOut();
  }, [done, signOut, status]);

  async function confirm() {
    if (!token) return;
    setBusy(true);
    setError(null);
    try {
      await signOutEverywhereWithLink(token);
      setDone(true);
    } catch (caught) {
      const kind = signOutLinkFailure(caught);
      if (kind === "other") setError(localizeError(caught, ui));
      else setFailure(kind);
    } finally {
      setBusy(false);
    }
  }

  if (done) {
    return (
      <AuthShell title={t("doneTitle")}>
        <div className="space-y-5 text-center">
          <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }} role="status">
            {t("doneBody")}
          </p>
          <Link className={`block ${primaryButtonClass}`} style={primaryButtonStyle} href="/forgot-password">
            {t("chooseNewPassword")}
          </Link>
          <Link className="text-sm font-semibold" style={{ color: "var(--dim)" }} href="/login">
            {t("signIn")}
          </Link>
        </div>
      </AuthShell>
    );
  }

  if (linkState === "missing" || failure) {
    const message =
      failure === "expired" ? t("linkExpired") : failure === "used" ? t("linkUsed") : t("linkInvalid");
    return (
      <AuthShell title={t("linkProblemTitle")}>
        <div className="space-y-5 text-center">
          <ErrorNotice className="text-start">{message}</ErrorNotice>
          <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>
            {t("linkProblemHelp")}
          </p>
          <Link className={`block ${primaryButtonClass}`} style={primaryButtonStyle} href="/login">
            {t("signIn")}
          </Link>
          <Link className="text-sm font-semibold" style={{ color: "var(--dim)" }} href="/forgot-password">
            {t("chooseNewPassword")}
          </Link>
        </div>
      </AuthShell>
    );
  }

  return (
    <AuthShell title={t("title")}>
      <div className="space-y-5">
        <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>
          {t("body")}
        </p>
        {error ? <AuthNotice>{error}</AuthNotice> : null}
        <button
          className={primaryButtonClass}
          style={primaryButtonStyle}
          disabled={busy || linkState !== "ready"}
          type="button"
          onClick={() => void confirm()}
        >
          {busy ? t("working") : t("confirm")}
        </button>
      </div>
    </AuthShell>
  );
}
