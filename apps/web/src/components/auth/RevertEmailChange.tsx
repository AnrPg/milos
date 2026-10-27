"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { useTranslations } from "next-intl";

import { revertEmailChange } from "@/api/email-change";
import { emailChangeLinkFailure, type EmailChangeLinkFailure } from "@/components/account/email-change-model";
import { AuthNotice, AuthShell, primaryButtonClass, primaryButtonStyle } from "@/components/auth/AuthShell";
import { resetTokenFromHash } from "@/components/auth/auth-errors";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

type LinkState = "reading" | "ready" | "missing";

/**
 * ADR-207: "this wasn't me", opened from the old address
 * (`/revert-email-change#token=...`). Puts the old address back, signs every
 * device out and pauses email changes for 7 days; the person should then
 * reset the password, since whoever changed the email knew it.
 */
export function RevertEmailChange() {
  const t = useTranslations("emailChange");
  const ui = useUiTranslations();
  const { status, signOut } = useSession();

  const [token, setToken] = useState<string | null>(null);
  const [linkState, setLinkState] = useState<LinkState>("reading");
  const [busy, setBusy] = useState(false);
  const [restored, setRestored] = useState<string | null>(null);
  const [failure, setFailure] = useState<EmailChangeLinkFailure | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const found = resetTokenFromHash(window.location.hash);
    queueMicrotask(() => {
      setToken(found);
      setLinkState(found ? "ready" : "missing");
    });
  }, []);

  // Every session ended with the revert, this one included.
  const signedOutRef = useRef(false);
  useEffect(() => {
    if (!restored || status !== "authenticated" || signedOutRef.current) return;
    signedOutRef.current = true;
    signOut();
  }, [restored, signOut, status]);

  async function revert() {
    if (!token || busy) return;
    setBusy(true);
    setError(null);
    try {
      const result = await revertEmailChange(token);
      setRestored(result.email);
    } catch (caught) {
      const kind = emailChangeLinkFailure(caught);
      if (kind === "other") setError(localizeError(caught, ui));
      else setFailure(kind);
    } finally {
      setBusy(false);
    }
  }

  if (restored) {
    return (
      <AuthShell title={t("revertedTitle")}>
        <div className="space-y-5 text-center">
          <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }} role="status">
            {t("revertedBody", { email: restored })}
          </p>
          <Link className={`block ${primaryButtonClass}`} style={primaryButtonStyle} href="/forgot-password">
            {t("resetPassword")}
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
              ? t("revertExpired")
              : failure === "unavailable"
                ? t("revertUnavailable")
                : t("linkInvalid")}
          </ErrorNotice>
          <Link className={`block ${primaryButtonClass}`} style={primaryButtonStyle} href="/forgot-password">
            {t("resetPassword")}
          </Link>
        </div>
      </AuthShell>
    );
  }

  return (
    <AuthShell title={t("revertTitle")}>
      <div className="space-y-5">
        <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>
          {t("revertBody")}
        </p>
        {error ? <AuthNotice>{error}</AuthNotice> : null}
        <button
          type="button"
          className={primaryButtonClass}
          style={primaryButtonStyle}
          disabled={busy || linkState !== "ready"}
          onClick={() => void revert()}
        >
          {busy ? t("reverting") : t("revertAction")}
        </button>
      </div>
    </AuthShell>
  );
}
