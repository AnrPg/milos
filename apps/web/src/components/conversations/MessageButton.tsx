"use client";

import { useTranslations } from "next-intl";

import { useUiTranslations } from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";

import { useOpenConversation } from "./use-conversations";

/**
 * «Message» on a person's profile (ADR-193 §3): opens (or finds) your
 * conversation with them and goes to it. Where it lands for them (inbox or
 * requests) is the API's call. Not shown on your own profile.
 */
export function MessageButton({ personId, name, wide = false }: { personId: string; name?: string | null; wide?: boolean }) {
  const t = useTranslations("Conversations");
  const tUi = useUiTranslations();
  const open = useOpenConversation();
  return (
    <div className={`flex flex-col gap-1 ${wide ? "w-full" : ""}`}>
      <button
        type="button"
        disabled={open.isPending}
        onClick={() => open.mutate(personId)}
        aria-label={name ? t("messageA11y", { name }) : undefined}
        className={`inline-flex min-h-11 items-center justify-center gap-2 rounded-2xl px-4 text-sm font-bold disabled:opacity-50 ${wide ? "w-full" : ""}`}
        style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
        data-testid="person-message-button"
      >
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M21.5 2.5 10.5 13.5" />
          <path d="M21.5 2.5 14.6 21a.5.5 0 0 1-.9 0l-3.2-7.5L3 10.3a.5.5 0 0 1 0-.9L21.5 2.5Z" />
        </svg>
        {t("message")}
      </button>
      {open.error ? (
        <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>
          {localizeError(open.error, tUi)}
        </p>
      ) : null}
    </div>
  );
}
