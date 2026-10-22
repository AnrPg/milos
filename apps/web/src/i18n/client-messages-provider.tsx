"use client";

import type { AbstractIntlMessages } from "next-intl";
import { NextIntlClientProvider } from "next-intl";
import { use } from "react";

import type { AppLocale } from "@/i18n/locales";

// ADR-178: the client reads the catalogue from its own content-hashed chunk
// (one per locale, cached by the browser for good) instead of receiving it
// inline in every page's HTML, where it was 450-700 KB on each full load.
const catalogues = new Map<AppLocale, Promise<AbstractIntlMessages>>();

function catalogue(locale: AppLocale) {
  let pending = catalogues.get(locale);
  if (!pending) {
    pending = import(`../../messages/${locale}.json`).then((module) => module.default as AbstractIntlMessages);
    catalogues.set(locale, pending);
  }
  return pending;
}

export function ClientMessagesProvider({
  locale,
  timeZone,
  children,
}: {
  locale: AppLocale;
  timeZone: string;
  children: React.ReactNode;
}) {
  const messages = use(catalogue(locale));
  return (
    <NextIntlClientProvider locale={locale} timeZone={timeZone} messages={messages}>
      {children}
    </NextIntlClientProvider>
  );
}
