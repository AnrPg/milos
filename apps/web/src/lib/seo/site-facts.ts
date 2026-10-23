import { getLocale, getTranslations } from "next-intl/server";

import { SUPPORTED_LOCALES, type AppLocale } from "@/i18n/locales";
import { siteOrigin } from "@/lib/site-url";

import { FEATURE_SECTIONS } from "./feature-catalog";
import { FAQ_KEYS, type FaqEntry, type SiteFacts } from "./site-info";

// Loads the facts in the given locale (the request's own when omitted).
export async function loadSiteFacts(locale?: AppLocale): Promise<{ facts: SiteFacts; faq: FaqEntry[] }> {
  const resolved = locale ?? (await getLocale());
  const info = await getTranslations({ locale: resolved, namespace: "SiteInfo" });
  return {
    facts: {
      origin: await siteOrigin(),
      description: info("whatIsAnswer"),
      overview: [info("twoSidesSummary")],
      features: FEATURE_SECTIONS.map(({ titleKey, summaryKey, details }) => ({
        title: info(titleKey),
        summary: info(summaryKey),
        details,
      })),
      languages: SUPPORTED_LOCALES,
    },
    faq: FAQ_KEYS.map(([question, answer]) => ({ question: info(question), answer: info(answer) })),
  };
}

