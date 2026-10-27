"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { useTranslations } from "next-intl";

import {
  resendVerificationEmail,
  verificationRetryAfter,
  verifyEmailToken,
  verifyLinkFailure,
  type VerifyLinkFailure,
} from "@/api/email-verification";
import { fetchCurrentUser } from "@/api/auth";
import { SESSION_UPDATED_EVENT } from "@/api/client";
import { AuthNotice, AuthShell, primaryButtonClass, primaryButtonStyle } from "@/components/auth/AuthShell";
import { resetTokenFromHash } from "@/components/auth/auth-errors";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { retryWait } from "@/lib/email-verification";

type PageState =
  | { kind: "reading" }
  | { kind: "confirming" }
  | { kind: "verified" }
  | { kind: "failed"; failure: VerifyLinkFailure | "missing"; message?: string };

type ResendState =
  | { kind: "idle" }
  | { kind: "sending" }
  | { kind: "sent" }
  | { kind: "wait"; seconds: number }
  | { kind: "failed"; message: string };

/**
 * ADR-213: the page the emailed link opens (`/verify-email#token=...`). The
 * token stays in the fragment, so mail scanners and server logs never see
 * it; the page posts it once. Works signed out (any device) and signed in,
 * where an expired or used link offers a new one.
 */
export function VerifyEmail() {
  const t = useTranslations("emailVerification");
  const ui = useUiTranslations();
  const { status, tokens, currentUser } = useSession();
  const [state, setState] = useState<PageState>({ kind: "reading" });
  const [resend, setResend] = useState<ResendState>({ kind: "idle" });
  const postedRef = useRef(false);

  // The fragment only exists in the browser; it is read once, then dropped
  // from the address bar so a reload or a shared URL does not carry it.
  useEffect(() => {
    if (postedRef.current) return;
    postedRef.current = true;
    const token = resetTokenFromHash(window.location.hash);
    if (window.location.hash) {
      window.history.replaceState(null, "", window.location.pathname + window.location.search);
    }
    if (!token) {
      queueMicrotask(() => setState({ kind: "failed", failure: "missing" }));
      return;
    }
    queueMicrotask(() => setState({ kind: "confirming" }));
    verifyEmailToken(token)
      .then(() => setState({ kind: "verified" }))
      .catch((caught: unknown) => {
        const failure = verifyLinkFailure(caught);
        setState({
          kind: "failed",
          failure,
          message: failure === "other" ? localizeError(caught, ui) : undefined,
        });
      });
  }, [ui]);

  // Signed in on this device: reload the session's user (the link may have
  // been for another login), so the banner goes away without a reload.
  const refreshedRef = useRef(false);
  useEffect(() => {
    if (state.kind !== "verified" || !tokens || !currentUser || currentUser.email_verified) return;
    if (refreshedRef.current) return;
    refreshedRef.current = true;
    fetchCurrentUser(tokens.access_token)
      .then((user) => {
        window.dispatchEvent(new CustomEvent(SESSION_UPDATED_EVENT, { detail: { tokens, currentUser: user } }));
      })
      .catch(() => undefined);
  }, [currentUser, state.kind, tokens]);

  const signedIn = status === "authenticated" && Boolean(currentUser);
  const continueHref = signedIn ? "/" : "/login";
  const continueLabel = signedIn ? t("continue") : t("signIn");

  if (state.kind === "reading" || state.kind === "confirming") {
    return (
      <AuthShell title={t("pageTitle")}>
        <p className="text-center text-sm leading-6" role="status" style={{ color: "var(--text-soft)" }}>
          {t("confirming")}
        </p>
      </AuthShell>
    );
  }

  // A used link for a login that is already confirmed is simply done.
  const alreadyVerified =
    state.kind === "failed" && state.failure === "used" && signedIn && currentUser?.email_verified === true;

  if (state.kind === "verified" || alreadyVerified) {
    return (
      <AuthShell title={t("verifiedTitle")}>
        <div className="space-y-5 text-center">
          <AuthNotice tone="success">{alreadyVerified ? t("alreadyVerifiedBody") : t("verifiedBody")}</AuthNotice>
          <Link className={`block ${primaryButtonClass}`} style={primaryButtonStyle} href={continueHref}>
            {continueLabel}
          </Link>
        </div>
      </AuthShell>
    );
  }

  async function sendNewLink() {
    if (!tokens) return;
    setResend({ kind: "sending" });
    try {
      const result = await resendVerificationEmail(tokens.access_token);
      setResend({ kind: result.status === "already_verified" ? "idle" : "sent" });
      if (result.status === "already_verified") setState({ kind: "verified" });
    } catch (caught) {
      const seconds = verificationRetryAfter(caught);
      setResend(seconds !== null ? { kind: "wait", seconds } : { kind: "failed", message: localizeError(caught, ui) });
    }
  }

  const failure = state.failure;
  const problem =
    failure === "expired"
      ? t("expiredBody")
      : failure === "used"
        ? t("usedBody")
        : failure === "email_changed"
          ? t("emailChangedBody")
          : failure === "other"
            ? (state.message ?? t("invalidBody"))
            : t("invalidBody");
  // A new link makes sense unless the address itself changed.
  const offerNewLink = failure !== "email_changed";

  return (
    <AuthShell title={t("problemTitle")}>
      <div className="space-y-5 text-center">
        <ErrorNotice className="text-start">{problem}</ErrorNotice>
        {resend.kind === "sent" ? (
          <AuthNotice tone="success">{t("newLinkSent", { email: currentUser?.email ?? "" })}</AuthNotice>
        ) : null}
        {resend.kind === "wait" ? (
          <p className="text-sm" role="status" style={{ color: "var(--text-soft)" }}>
            {(() => {
              const wait = retryWait(resend.seconds);
              return wait.kind === "seconds" ? t("throttled", { seconds: wait.seconds }) : t("throttledLong");
            })()}
          </p>
        ) : null}
        {resend.kind === "failed" ? <AuthNotice>{resend.message}</AuthNotice> : null}
        {offerNewLink && signedIn && resend.kind !== "sent" ? (
          <button
            type="button"
            className={primaryButtonClass}
            style={primaryButtonStyle}
            disabled={resend.kind === "sending"}
            onClick={() => void sendNewLink()}
          >
            {resend.kind === "sending" ? t("resending") : t("sendNewLink")}
          </button>
        ) : null}
        {offerNewLink && !signedIn ? (
          <Link className={`block ${primaryButtonClass}`} style={primaryButtonStyle} href="/login">
            {t("signInForNewLink")}
          </Link>
        ) : null}
        {signedIn || !offerNewLink ? (
          <Link className="text-sm font-semibold" style={{ color: "var(--dim)" }} href={continueHref}>
            {continueLabel}
          </Link>
        ) : null}
      </div>
    </AuthShell>
  );
}
