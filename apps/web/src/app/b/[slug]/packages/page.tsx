import type { Metadata } from "next";
import { notFound, permanentRedirect } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { Suspense } from "react";

import { SalesPage } from "@/components/payments/SalesPage";
import { loadPublicBox, previewLine } from "@/lib/public-box";

type Props = { params: Promise<{ slug: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const page = await loadPublicBox(slug);
  if (!page) return {};
  const t = await getTranslations("Pay");
  const title = t("salesTitle", { box: page.box.name });
  return {
    title,
    alternates: { canonical: `/b/${page.box.slug}/packages` },
    openGraph: { title, type: "website", url: `/b/${page.box.slug}/packages` },
  };
}

/**
 * The box's sales page (ADR-248, mockup s5 option C): reached from the
 * public box page and the box's sign-up links.
 */
export default async function SalesRoute({ params }: Props) {
  const { slug } = await params;
  const page = await loadPublicBox(slug);
  if (!page) notFound();
  if (page.box.slug !== slug) permanentRedirect(`/b/${page.box.slug}/packages`);
  const tags = await getTranslations("BoxTags");
  const line = previewLine(page, (key) => tags(`discipline.${key}`));
  return (
    <Suspense>
      <SalesPage page={page} line={line} />
    </Suspense>
  );
}
