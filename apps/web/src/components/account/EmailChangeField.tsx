"use client";

import { useEffect, useState } from "react";
import { useFormatter, useTranslations } from "next-intl";

import {
  cancelEmailChange,
  fetchEmailChange,
  requestEmailChange,
  resendEmailChange,
  type EmailChangeStatus,
} from "@/api/email-change";
import { describeEmailChangeError } from "@/components/account/email-change-model";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

const inputStyle = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" };
const quietButtonClass = "rounded-xl px-4 py-2 text-sm font-semibold disabled:opacity-50";
const quietButtonStyle = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" };

/**
 * Ρυθμίσεις › Personal info › Email (ADR-207). The account's email changes
 * only once the new address opens the link mailed to it; until then the
 * current one keeps working for sign-in and resets. Lives inside the
 * identity form, so its controls are buttons, not a nested form.
 */
export function EmailChangeField() {
  const t = useTranslations("emailChange");
  const ui = useUiTranslations();
  const format = useFormatter();
  const { tokens, currentUser } = useSession();
  const [status, setStatus] = useState<EmailChangeStatus | null>(null);
  const [editing, setEditing] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);

  const accessToken = tokens?.access_token;
  useEffect(() => {
    if (!accessToken) return;
    let live = true;
    fetchEmailChange(accessToken)
      .then((next) => {
        if (live) setStatus(next);
      })
      .catch(() => {
        if (live) setStatus({ pending: null, locked_until: null });
      });
    return () => {
      live = false;
    };
  }, [accessToken]);

  function explain(caught: unknown) {
    const described = describeEmailChangeError(caught);
    setError(described ? t(described.key, described.values) : localizeError(caught, ui));
  }

  async function run(action: () => Promise<EmailChangeStatus>, after?: () => void) {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      setStatus(await action());
      after?.();
    } catch (caught) {
      explain(caught);
    } finally {
      setBusy(false);
    }
  }

  function submit() {
    if (!accessToken) return;
    if (!email.trim()) return setError(t("errors.invalidEmail"));
    if (!password) return setError(t("errors.passwordNeeded"));
    void run(
      () => requestEmailChange(accessToken, email.trim(), password),
      () => {
        setEditing(false);
        setEmail("");
        setPassword("");
        setSent(true);
      },
    );
  }

  function submitOnEnter(event: React.KeyboardEvent<HTMLInputElement>) {
    if (event.key !== "Enter") return;
    // The identity form around this field must not submit.
    event.preventDefault();
    submit();
  }

  const pending = status?.pending ?? null;
  const lockedUntil = status?.locked_until ? new Date(status.locked_until) : null;
  const current = currentUser?.email ?? "";

  return (
    <div className="space-y-3" data-testid="email-change">
      <div className="space-y-1.5">
        <p className="block text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--muted)" }}>
          {t("label")}
        </p>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <p className="min-w-0 break-all text-sm font-semibold" style={{ color: "var(--text)" }} dir="ltr">
            {current}
          </p>
          {!editing && !pending && !lockedUntil ? (
            <button
              type="button"
              className={quietButtonClass}
              style={quietButtonStyle}
              onClick={() => {
                setEditing(true);
                setSent(false);
                setError(null);
              }}
            >
              {t("change")}
            </button>
          ) : null}
        </div>
      </div>

      {pending ? (
        <div
          className="space-y-3 rounded-2xl px-4 py-3"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
          data-testid="email-change-pending"
          role="status"
        >
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {t("pendingTitle", { email: pending.email })}
          </p>
          <p className="text-xs leading-5" style={{ color: "var(--muted)" }}>
            {sent ? `${t("sent")} ` : ""}
            {t("pendingBody", {
              current,
              until: format.dateTime(new Date(pending.expires_at), { dateStyle: "medium", timeStyle: "short" }),
            })}
          </p>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              disabled={busy || !accessToken}
              className={quietButtonClass}
              style={quietButtonStyle}
              onClick={() => accessToken && void run(() => resendEmailChange(accessToken), () => setSent(true))}
            >
              {t("resend")}
            </button>
            <button
              type="button"
              disabled={busy || !accessToken}
              className={quietButtonClass}
              style={{ ...quietButtonStyle, color: "var(--danger-strong)" }}
              onClick={() => accessToken && void run(() => cancelEmailChange(accessToken), () => setSent(false))}
            >
              {t("cancelChange")}
            </button>
          </div>
        </div>
      ) : null}

      {lockedUntil ? (
        <p className="text-xs leading-5" style={{ color: "var(--muted)" }} data-testid="email-change-locked">
          {t("lockedBody", { date: lockedUntil })}
        </p>
      ) : null}

      {editing ? (
        <div className="space-y-3">
          <div className="space-y-1.5">
            <label htmlFor="email-change-new" className="block text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--muted)" }}>
              {t("newLabel")}
            </label>
            <input
              id="email-change-new"
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              onKeyDown={submitOnEnter}
              autoComplete="email"
              className="w-full rounded-xl px-4 py-2.5 text-sm outline-none"
              style={inputStyle}
              dir="ltr"
            />
          </div>
          <div className="space-y-1.5">
            <label htmlFor="email-change-password" className="block text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--muted)" }}>
              {t("passwordLabel")}
            </label>
            <input
              id="email-change-password"
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              onKeyDown={submitOnEnter}
              autoComplete="current-password"
              className="w-full rounded-xl px-4 py-2.5 text-sm outline-none"
              style={inputStyle}
            />
          </div>
          <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>
            {t("hint")}
          </p>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              disabled={busy}
              onClick={submit}
              className="rounded-xl px-4 py-2 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            >
              {busy ? t("sending") : t("send")}
            </button>
            <button
              type="button"
              disabled={busy}
              className={quietButtonClass}
              style={quietButtonStyle}
              onClick={() => {
                setEditing(false);
                setError(null);
                setPassword("");
              }}
            >
              {t("cancel")}
            </button>
          </div>
        </div>
      ) : null}

      {error ? <ErrorNotice>{error}</ErrorNotice> : null}
    </div>
  );
}
