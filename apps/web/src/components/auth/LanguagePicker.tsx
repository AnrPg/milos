"use client";

import { useRouter } from "next/navigation";
import { useTranslations } from "next-intl";
import { useTransition } from "react";

import { isAppLocale, LOCALE_NAMES, persistLocaleCookie, SUPPORTED_LOCALES, type AppLocale } from "@/i18n/locales";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { Select } from "@/components/ui/Select";

/**
 * ADR-195: the language switch on the signed-out pages (sign in, sign up,
 * password reset, business sign-up). It writes the same locale cookie the
 * profile setting does and re-renders in place, so what the person already
 * typed stays. Sign-up sends this language as the new account's own.
 */
export function LanguagePicker({ className = "" }: { className?: string }) {
  const t = useTranslations("Profile");
  const locale = useUiLocale();
  const router = useRouter();
  const [pending, startTransition] = useTransition();

  function choose(next: string) {
    if (!isAppLocale(next) || next === locale) return;
    persistLocaleCookie(next);
    startTransition(() => router.refresh());
  }

  return (
    <div className={`inline-flex items-center gap-1.5 ${className}`} data-language-picker>
      <GlobeIcon />
      <Select
        aria-label={t("languageLabel")}
        value={locale}
        disabled={pending}
        onValueChange={choose}
        className="rounded-full px-3 py-1.5 text-xs font-semibold outline-none"
        style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
      >
        {SUPPORTED_LOCALES.map((option: AppLocale) => (
          <option key={option} value={option}>
            {LOCALE_NAMES[option]}
          </option>
        ))}
      </Select>
    </div>
  );
}

function GlobeIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 20 20" fill="none" className="h-4 w-4" style={{ color: "var(--dim)" }}>
      <circle cx="10" cy="10" r="7.25" stroke="currentColor" strokeWidth="1.5" />
      <path d="M2.75 10h14.5M10 2.75c2 2.1 3 4.5 3 7.25s-1 5.15-3 7.25c-2-2.1-3-4.5-3-7.25s1-5.15 3-7.25Z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
    </svg>
  );
}
