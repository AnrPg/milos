"use client";

import { useLocale, useTranslations } from "next-intl";
import { useEffect, useState } from "react";

import type { PasswordResetLink } from "@/api/password-resets";
import { buildMailto, resetLinkFor } from "@/components/password-resets/reset-email";
import { formatClock } from "@/lib/clock";

type Field = "to" | "subject" | "body" | "link";

/**
 * The send page: the handler mails the one-time link from their own
 * mailbox. "Open in mail app" fills everything in; each part can also be
 * copied for webmail or another app.
 */
export function SendPanel({
  link,
  personName,
  personHandle,
  sender,
  onDone,
}: {
  link: PasswordResetLink;
  personName: string;
  personHandle: string;
  sender: string;
  onDone: () => void;
}) {
  const t = useTranslations("passwordResets");
  const locale = useLocale();
  // Rendered only after the link was created in the browser, never on the server.
  const origin = typeof window === "undefined" ? "" : window.location.origin;
  const [copied, setCopied] = useState<Field | null>(null);

  useEffect(() => {
    if (!copied) return;
    const timer = window.setTimeout(() => setCopied(null), 2000);
    return () => window.clearTimeout(timer);
  }, [copied]);

  const resetLink = origin ? resetLinkFor(origin, link.token) : "";
  const subject = t("emailSubject");
  const body = t("emailBody", { name: personName, handle: personHandle, link: resetLink, sender });
  const mailto = buildMailto({ to: link.email, subject, body });
  const validUntil = formatClock(new Date(link.expires_at), locale, { dateStyle: "medium", timeStyle: "short" });

  const fields: Array<{ id: Field; label: string; value: string; multiline?: boolean }> = [
    { id: "to", label: t("fieldTo"), value: link.email },
    { id: "subject", label: t("fieldSubject"), value: subject },
    { id: "body", label: t("fieldBody"), value: body, multiline: true },
    { id: "link", label: t("fieldLink"), value: resetLink },
  ];

  async function copy(field: Field, value: string) {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(field);
    } catch {
      setCopied(null);
    }
  }

  return (
    <section className="flex flex-col gap-4">
      <div className="flex flex-col gap-1">
        <h2 className="text-lg font-semibold text-[var(--text)]">{t("sendTitle")}</h2>
        <p className="text-sm text-[var(--text-soft)]">{t("sendIntro")}</p>
        <p className="text-xs text-[var(--dim)]">{t("validUntil", { time: validUntil })}</p>
      </div>

      <a
        href={mailto}
        aria-disabled={!resetLink}
        className="rounded-full bg-[var(--accent)] px-5 py-3.5 text-center text-base font-semibold text-[var(--primary-contrast)] aria-disabled:pointer-events-none aria-disabled:opacity-40"
      >
        {t("openMail")}
      </a>

      <dl className="flex flex-col divide-y divide-[var(--border)] rounded-2xl border border-[var(--border)] bg-[var(--panel)]">
        {fields.map((field) => (
          <div key={field.id} className="flex items-start gap-3 px-4 py-3">
            <div className="min-w-0 flex-1">
              <dt className="text-xs font-bold uppercase tracking-[0.14em] text-[var(--dim)]">{field.label}</dt>
              <dd
                className={`mt-1 break-words text-sm text-[var(--text)] ${field.multiline ? "whitespace-pre-line" : ""}`}
                dir="auto"
              >
                {field.value}
              </dd>
            </div>
            <button
              type="button"
              onClick={() => void copy(field.id, field.value)}
              aria-label={t("copyNamed", { field: field.label })}
              className="shrink-0 rounded-full border border-[var(--border)] px-3 py-1.5 text-xs font-semibold text-[var(--text-soft)]"
            >
              <span aria-live="polite">{copied === field.id ? t("copied") : t("copy")}</span>
            </button>
          </div>
        ))}
      </dl>

      <button
        type="button"
        onClick={onDone}
        className="self-start rounded-full border border-[var(--border)] px-4 py-2.5 text-sm font-semibold text-[var(--text-soft)]"
      >
        {t("done")}
      </button>
    </section>
  );
}
