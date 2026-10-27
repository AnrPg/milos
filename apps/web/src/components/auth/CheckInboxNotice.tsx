"use client";

import { useTranslations } from "next-intl";

import { primaryButtonClass, primaryButtonStyle } from "@/components/auth/AuthShell";

/**
 * ADR-211: what every sign-up shows once the server answered "a link was
 * sent". It looks the same whether the email was new (a confirmation link
 * went out, the session is open) or already had an account (the owner was
 * told someone tried), so the form never says which. "Continue" goes on to
 * the app for a new account, and to sign-in otherwise.
 */
export function CheckInboxNotice({ email, onContinue }: { email: string; onContinue: () => void }) {
  const t = useTranslations("signupInbox");

  return (
    <section className="space-y-5 text-center" aria-labelledby="check-inbox-title">
      <div
        aria-hidden="true"
        className="mx-auto flex h-14 w-14 items-center justify-center rounded-full text-2xl"
        style={{ background: "color-mix(in srgb, var(--primary) 12%, transparent)", color: "var(--primary)" }}
      >
        ✉
      </div>
      <h2 id="check-inbox-title" className="text-xl font-bold" style={{ color: "var(--text)" }}>
        {t("title")}
      </h2>
      <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>
        {t.rich("sentTo", { email, strong: (chunks) => <strong style={{ color: "var(--text)" }}>{chunks}</strong> })}
      </p>
      <p className="text-xs leading-5" style={{ color: "var(--muted)" }}>
        {t("spamHint")}
      </p>
      <button type="button" className={primaryButtonClass} style={primaryButtonStyle} onClick={onContinue}>
        {t("continue")}
      </button>
    </section>
  );
}
