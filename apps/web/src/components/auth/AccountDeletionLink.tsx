"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { useFormatter, useTranslations } from "next-intl";

import { confirmAccountDeletion, undoAccountDeletion, type AccountDeletion } from "@/api/account-deletion";
import { deletionLinkFailure, type DeletionLinkFailure } from "@/components/account/account-deletion-model";
import { AuthNotice, AuthShell, primaryButtonClass, primaryButtonStyle } from "@/components/auth/AuthShell";
import { resetTokenFromHash } from "@/components/auth/auth-errors";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

type Mode = "confirm" | "undo";
type LinkState = "reading" | "ready" | "missing";

/**
 * ADR-211: the pages the deletion emails open, `/account-deletion/confirm`
 * and `/account-deletion/undo`, with the token in the fragment so it never
 * reaches a server log. Nothing happens until the person presses the button,
 * so a mail scanner opening the link changes nothing.
 */
export function AccountDeletionLink({ mode }: { mode: Mode }) {
  const t = useTranslations("accountDeletion");
  const ui = useUiTranslations();
  const format = useFormatter();
  const { status, signOut } = useSession();
  const [token, setToken] = useState<string | null>(null);
  const [linkState, setLinkState] = useState<LinkState>("reading");
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<AccountDeletion | null>(null);
  const [failure, setFailure] = useState<DeletionLinkFailure | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const found = resetTokenFromHash(window.location.hash);
    queueMicrotask(() => {
      setToken(found);
      setLinkState(found ? "ready" : "missing");
    });
  }, []);

  // A confirmed deletion ended the sessions of what it deletes.
  const signedOutRef = useRef(false);
  useEffect(() => {
    if (mode !== "confirm" || !done || status !== "authenticated" || signedOutRef.current) return;
    signedOutRef.current = true;
    signOut();
  }, [done, mode, signOut, status]);

  async function submit() {
    if (!token) return;
    setBusy(true);
    setError(null);
    try {
      setDone(mode === "confirm" ? await confirmAccountDeletion(token) : await undoAccountDeletion(token));
    } catch (caught) {
      const kind = deletionLinkFailure(caught);
      if (kind === "other") setError(localizeError(caught, ui));
      else setFailure(kind);
    } finally {
      setBusy(false);
    }
  }

  if (done) {
    const date = done.scheduled_for ? format.dateTime(new Date(done.scheduled_for), { dateStyle: "long" }) : "";
    const message =
      mode === "undo"
        ? t("undoDone")
        : done.scope === "profile"
          ? t("confirmDoneProfile", { date })
          : t("confirmDoneAccount", { date });

    return (
      <AuthShell title={mode === "confirm" ? t("confirmTitle") : t("undoTitle")}>
        <div className="space-y-5 text-center">
          <AuthNotice tone="success">{message}</AuthNotice>
          <Link className={`block ${primaryButtonClass}`} style={primaryButtonStyle} href="/login">
            {t("toSignIn")}
          </Link>
        </div>
      </AuthShell>
    );
  }

  if (linkState === "missing" || failure) {
    return (
      <AuthShell title={mode === "confirm" ? t("confirmTitle") : t("undoTitle")}>
        <div className="space-y-5 text-center">
          <ErrorNotice className="text-start">
            {failure === "expired" ? t("linkExpired") : failure === "invalid" ? t("linkInvalid") : t("linkMissing")}
          </ErrorNotice>
          <Link className={`block ${primaryButtonClass}`} style={primaryButtonStyle} href="/login">
            {t("toSignIn")}
          </Link>
        </div>
      </AuthShell>
    );
  }

  return (
    <AuthShell title={mode === "confirm" ? t("confirmTitle") : t("undoTitle")}>
      <div className="space-y-5">
        <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>
          {mode === "confirm" ? t("confirmIntro") : t("undoIntro")}
        </p>
        {error ? <AuthNotice>{error}</AuthNotice> : null}
        <button
          type="button"
          className={primaryButtonClass}
          style={mode === "confirm" ? { background: "var(--danger)", color: "var(--danger-contrast)" } : primaryButtonStyle}
          disabled={busy || linkState !== "ready"}
          onClick={() => void submit()}
        >
          {mode === "confirm" ? t("confirmButton") : t("undoButton")}
        </button>
      </div>
    </AuthShell>
  );
}
