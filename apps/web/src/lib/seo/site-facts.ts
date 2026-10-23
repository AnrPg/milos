import { getLocale, getTranslations } from "next-intl/server";

import { SUPPORTED_LOCALES, type AppLocale } from "@/i18n/locales";
import { siteOrigin } from "@/lib/site-url";

import { FAQ_KEYS, type FaqEntry, type SiteFacts } from "./site-info";

// Loads the facts in the given locale (the request's own when omitted).
export async function loadSiteFacts(locale?: AppLocale): Promise<{ facts: SiteFacts; faq: FaqEntry[] }> {
  const resolved = locale ?? (await getLocale());
  const ui = await getTranslations({ locale: resolved, namespace: "Ui" });
  const info = await getTranslations({ locale: resolved, namespace: "SiteInfo" });
  return {
    facts: {
      origin: await siteOrigin(),
      description: ui("onePrivateSelfHostedHomeForGroupClasses89e3bcd"),
      features: [
        `${ui("members1cb449c")}: ${ui("bookClassesFollowGymUpdatesAndKeepAttendancec7408d8")}`,
        `${ui("athletesda22204")}: ${ui("executeTailoredTrainingWithAStepSynchronisedTimer9c0485e")}`,
        `${ui("coaches181feb6")}: ${ui("programCommunicateAndUnderstandTrainingProgressWithoutSurveillance7c67d89")}`,
      ],
      languages: SUPPORTED_LOCALES,
    },
    faq: FAQ_KEYS.map(([question, answer]) => ({ question: info(question), answer: info(answer) })),
  };
}

