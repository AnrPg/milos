"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useTranslations } from "next-intl";
import { useEffect, useState } from "react";

import { resendVerificationEmail, verificationRetryAfter } from "@/api/email-verification";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import {
  BANNER_DISMISS_KEY,
  CHANGE_EMAIL_HREF,
  retryWait,
  showsVerificationBanner,
} from "@/lib/email-verification";

type ResendState =
  | { kind: "idle" }
  | { kind: "sending" }
  | { kind: "sent" }
  | { kind: "throttled"; seconds: number }
  | { kind: "error"; message: string };

function readDismissed() {
  try {
    return window.sessionStorage.getItem(BANNER_DISMISS_KEY) === "1";
  } catch {
    return false;
  }
}

/**
 * ADR-213: one quiet line for a signed-in person whose email is not
 * confirmed yet: resend the link, or change the address in Settings.
 * Hidden for the rest of the browser session once dismissed.
 */
export function EmailVerificationBanner() {
  const t = useTranslations("emailVerification");
  const ui = useUiTranslations();
  const pathname = usePathname();
  const { currentUser, tokens } = useSession();
  const [dismissed, setDismissed] = useState(true);
  const [state, setState] = useState<ResendState>({ kind: "idle" });

  // sessionStorage only exists in the browser.
  useEffect(() => {
    const stored = readDismissed();
    queueMicrotask(() => setDismissed(stored));
  }, []);

  if (!showsVerificationBanner({ pathname, user: currentUser, dismissed })) return null;

  function dismiss() {
    try {
      window.sessionStorage.setItem(BANNER_DISMISS_KEY, "1");
    } catch {
      // Private mode: hidden until the next page load.
    }
    setDismissed(true);
  }

  async function resend() {
    if (!tokens) return;
    setState({ kind: "sending" });
    try {
      await resendVerificationEmail(tokens.access_token);
      setState({ kind: "sent" });
    } catch (caught) {
      const seconds = verificationRetryAfter(caught);
      if (seconds !== null) setState({ kind: "throttled", seconds });
      else setState({ kind: "error", message: localizeError(caught, ui) });
    }
  }

  const wait = state.kind === "throttled" ? retryWait(state.seconds) : null;

  return (
    <div
      className="px-4 py-2 text-sm"
      data-testid="email-verification-banner"
      role="region"
      aria-label={t("pageTitle")}
      style={{ background: "var(--panel)", borderBottom: "1px solid var(--border)", color: "var(--text-soft)" }}
    >
      <div className="mx-auto flex max-w-5xl flex-wrap items-center gap-x-3 gap-y-1">
        <p className="min-w-0 flex-1">{t("bannerText", { email: currentUser?.email ?? "" })}</p>
        {state.kind === "sent" ? (
          <span role="status" style={{ color: "var(--success)" }}>
            {t("resent")}
          </span>
        ) : wait ? (
          <span role="status">
            {wait.kind === "seconds" ? t("throttled", { seconds: wait.seconds }) : t("throttledLong")}
          </span>
        ) : (
          <button
            type="button"
            className="font-semibold disabled:opacity-60"
            style={{ color: "var(--primary)" }}
            disabled={state.kind === "sending"}
            onClick={() => void resend()}
          >
            {state.kind === "sending" ? t("resending") : t("resend")}
          </button>
        )}
        <Link className="font-semibold" style={{ color: "var(--primary)" }} href={CHANGE_EMAIL_HREF}>
          {t("changeEmail")}
        </Link>
        <button
          type="button"
          aria-label={t("dismiss")}
          title={t("dismiss")}
          className="rounded-full px-2 leading-none"
          style={{ color: "var(--dim)" }}
          onClick={dismiss}
        >
          <span aria-hidden>×</span>
        </button>
      </div>
      {state.kind === "error" ? (
        <div className="mx-auto mt-2 max-w-5xl">
          <ErrorNotice variant="field">{state.message}</ErrorNotice>
        </div>
      ) : null}
    </div>
  );
}
