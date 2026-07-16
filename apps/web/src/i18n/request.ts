import { cookies, headers } from "next/headers";
import { getRequestConfig } from "next-intl/server";

import {
  DEFAULT_LOCALE,
  isAppLocale,
  LOCALE_COOKIE,
  type AppLocale,
} from "@/i18n/locales";

function browserLocale(acceptLanguage: string | null): AppLocale | null {
  if (!acceptLanguage) return null;

  for (const candidate of acceptLanguage.split(",")) {
    const tag = candidate.split(";", 1)[0]?.trim();
    if (!tag) continue;
    if (isAppLocale(tag)) return tag;

    const base = tag.split("-", 1)[0]?.toLowerCase();
    if (base === "pt") return "pt-PT";
    if (isAppLocale(base)) return base;
  }

  return null;
}

export default getRequestConfig(async () => {
  const cookieLocale = (await cookies()).get(LOCALE_COOKIE)?.value;
  const locale =
    (isAppLocale(cookieLocale) && cookieLocale) ||
    browserLocale((await headers()).get("accept-language")) ||
    DEFAULT_LOCALE;

  return {
    locale,
    messages: (await import(`../../messages/${locale}.json`)).default,
  };
});
