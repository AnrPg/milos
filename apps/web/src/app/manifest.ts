import type { MetadataRoute } from "next";
import { getLocale, getTranslations } from "next-intl/server";

import { DEFAULT_LOCALE, isAppLocale, localeDirection } from "@/i18n/locales";

export default async function manifest(): Promise<MetadataRoute.Manifest> {
  const requestedLocale = await getLocale();
  const locale = isAppLocale(requestedLocale) ? requestedLocale : DEFAULT_LOCALE;
  const translate = await getTranslations("Ui");
  return {
    name: "Milos Training",
    short_name: "Milos",
    description: translate("manifestDescription"),
    lang: locale,
    dir: localeDirection(locale),
    start_url: "/",
    display: "standalone",
    background_color: "#0b0d10",
    theme_color: "#c9ff45",
    orientation: "any",
    categories: ["fitness", "health", "sports"],
    icons: [
      { src: "/icon.svg", sizes: "any", type: "image/svg+xml", purpose: "any" },
      { src: "/icon-maskable.svg", sizes: "any", type: "image/svg+xml", purpose: "maskable" },
    ],
  };
}
