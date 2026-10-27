"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useTranslations } from "next-intl";

import type { AuthTokens } from "@/api/auth";
import { confirmEmailChange } from "@/api/email-change";
import { emailChangeLinkFailure, type EmailChangeLinkFailure } from "@/components/account/email-change-model";
import { AuthNotice, AuthShell, primaryButtonClass, primaryButtonStyle } from "@/components/auth/AuthShell";
import { resetTokenFromHash } from "@/components/auth/auth-errors";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

type LinkState = "reading" | "ready" | "missing";
type Done = { email: string; signedIn: boolean };

/**
 * ADR-207: the page the link to a new address opens
 * (`/confirm-email-change#token=...`). Nothing happens until the person
 * presses the button, so a mail scanner that opens links changes nothing.
 * Every session ends; this browser keeps one when it was signed in to the
 * same account.
 */
export function ConfirmEmailChange() {
  const t = useTranslations("emailChange");
  const ui = useUiTranslations();
  const { status, switchSession, signOut } = useSession();

  const [token, setToken] = useState<string | null>(null);
  const [linkState, setLinkState] = useState<LinkState>("reading");
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<Done | null>(null);
  const [failure, setFailure] = useState<EmailChangeLinkFailure | null>(null);
  const [error, setError] = useState<string | null>(null);

  // The fragment only exists in the browser.
  useEffect(() => {
    const found = resetTokenFromHash(window.location.hash);
    queueMicrotask(() => {
      setToken(found);
      setLinkState(found ? "ready" : "missing");
    });
  }, []);

  async function confirm() {
    if (!token || busy) return;
    setBusy(true);
    setError(null);
    try {
      const result = await confirmEmailChange(token);
      if (result.access_token) {
        await switchSession({ access_token: result.access_token, user: result.user } as AuthTokens);
        setDone({ email: result.email, signedIn: true });
      } else {
        // Any session this browser held ended with the change.
        if (status === "authenticated") signOut();
        setDone({ email: result.email, signedIn: false });
      }
    } catch (caught) {
      const kind = emailChangeLinkFailure(caught);
      if (kind === "other") setError(localizeError(caught, ui));
      else setFailure(kind);
    } finally {
      setBusy(false);
    }
  }

  if (done) {
    return (
      <AuthShell title={t("confirmedTitle")}>
        <div className="space-y-5 text-center">
          <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }} role="status">
            {t("confirmedBody", { email: done.email })}
          </p>
          <Link
            className={`block ${primaryButtonClass}`}
            style={primaryButtonStyle}
            href={done.signedIn ? "/me/settings#personal" : "/login"}
          >
            {done.signedIn ? t("toSettings") : t("signIn")}
          </Link>
        </div>
      </AuthShell>
    );
  }

  if (linkState === "missing" || failure) {
    return (
      <AuthShell title={t("linkProblemTitle")}>
        <div className="space-y-5 text-center">
          <ErrorNotice className="text-start">
            {failure === "expired"
              ? t("confirmExpired")
              : failure === "unavailable"
                ? t("confirmUnavailable")
                : t("linkInvalid")}
          </ErrorNotice>
          <Link className={`block ${primaryButtonClass}`} style={primaryButtonStyle} href="/me/settings#personal">
            {t("toSettings")}
          </Link>
        </div>
      </AuthShell>
    );
  }

  return (
    <AuthShell title={t("confirmTitle")}>
      <div className="space-y-5">
        <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>
          {t("confirmBody")}
        </p>
        {error ? <AuthNotice>{error}</AuthNotice> : null}
        <button
          type="button"
          className={primaryButtonClass}
          style={primaryButtonStyle}
          disabled={busy || linkState !== "ready"}
          onClick={() => void confirm()}
        >
          {busy ? t("confirming") : t("confirmAction")}
        </button>
      </div>
    </AuthShell>
  );
}
