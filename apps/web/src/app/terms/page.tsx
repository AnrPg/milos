import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";

import { LegalPage, LegalSection, legalPlaceholders } from "@/components/legal/LegalPage";

export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations("legal");
  const title = t("termsTitle");
  const description = t("terms.intro");
  return {
    title,
    description,
    alternates: { canonical: "/terms" },
    openGraph: { title, description, url: "/terms" },
  };
}

// Each section: its anchor, then the keys of its heading and text in `legal.terms`.
const SECTIONS = [
  { id: "account", heading: "accountTitle", text: "accountBody" },
  { id: "boxes", heading: "boxesTitle", text: "boxesBody" },
  { id: "payments", heading: "paymentsTitle", text: "paymentsBody" },
  { id: "content", heading: "contentTitle", text: "contentBody" },
  { id: "health", heading: "healthTitle", text: "healthBody" },
  { id: "ai", heading: "aiTitle", text: "aiBody" },
  { id: "availability", heading: "availabilityTitle", text: "availabilityBody" },
  { id: "ending", heading: "endingTitle", text: "endingBody" },
  { id: "liability", heading: "liabilityTitle", text: "liabilityBody" },
  { id: "law", heading: "lawTitle", text: "lawBody" },
  { id: "changes", heading: "changesTitle", text: "changesBody" },
] as const;

/** ADR-267: Palee's terms of use, a draft for the law consultant. */
export default async function TermsPage() {
  const t = await getTranslations("legal");
  const terms = await getTranslations("legal.terms");
  const values = await legalPlaceholders();

  return (
    <LegalPage title={t("termsTitle")} intro={terms("intro")} current="terms">
      <LegalSection id="provider" title={terms("providerTitle")}>
        <p>{terms("providerBody", values)}</p>
      </LegalSection>
      {SECTIONS.map((section) => (
        <LegalSection key={section.id} id={section.id} title={terms(section.heading)}>
          <p>{terms(section.text, values)}</p>
        </LegalSection>
      ))}
    </LegalPage>
  );
}
