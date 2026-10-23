import type { Metadata } from "next";

import { ProductOverview } from "@/components/about/ProductOverview";
import { JsonLd } from "@/components/seo/JsonLd";
import { getUiTranslations } from "@/i18n/ui-server";
import { loadSiteFacts } from "@/lib/seo/site-facts";
import { faqStructuredData } from "@/lib/seo/site-info";

export async function generateMetadata(): Promise<Metadata> {
  const i18n = await getUiTranslations();
  const title = i18n("aboutPalee");
  const description = i18n("howPaleeSupportsMembersAthletesAndCoaches");
  return {
    title,
    description,
    alternates: { canonical: "/about" },
    openGraph: { title, description, url: "/about" },
  };
}

export default async function AboutPage() {
  const { facts, faq } = await loadSiteFacts();
  return (
    <main className="flex w-full flex-1">
      <JsonLd data={faqStructuredData(faq)} />
      <ProductOverview faq={faq} features={facts.features} />
    </main>
  );
}
