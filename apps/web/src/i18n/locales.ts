export const SUPPORTED_LOCALES = [
  "en",
  "el",
  "ar",
  "ru",
  "de",
  "es",
  "pt-PT",
  "he",
  "it",
  "bg",
  "nl",
  "fr",
] as const;

export type AppLocale = (typeof SUPPORTED_LOCALES)[number];

export const DEFAULT_LOCALE: AppLocale = "en";
export const LOCALE_COOKIE = "milos_locale";
export const RTL_LOCALES = new Set<AppLocale>(["ar", "he"]);

export const LOCALE_NAMES: Record<AppLocale, string> = {
  en: "English",
  el: "Ελληνικά",
  ar: "العربية",
  ru: "Русский",
  de: "Deutsch",
  es: "Español",
  "pt-PT": "Português",
  he: "עברית",
  it: "Italiano",
  bg: "Български",
  nl: "Nederlands",
  fr: "Français",
};

export function isAppLocale(value: string | null | undefined): value is AppLocale {
  return SUPPORTED_LOCALES.includes(value as AppLocale);
}

export function localeDirection(locale: AppLocale) {
  return RTL_LOCALES.has(locale) ? "rtl" : "ltr";
}

export function persistLocaleCookie(locale: AppLocale) {
  document.cookie = `${LOCALE_COOKIE}=${encodeURIComponent(locale)}; Path=/; Max-Age=31536000; SameSite=Lax`;
  document.documentElement.lang = locale;
  document.documentElement.dir = localeDirection(locale);
}
