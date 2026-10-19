import type { Metadata } from "next";
import { notFound, permanentRedirect } from "next/navigation";
import { getTranslations } from "next-intl/server";

import { PublicBoxView } from "@/components/box-page/PublicBoxView";
import { loadPublicBox, previewLine } from "@/lib/public-box";

type Props = { params: Promise<{ slug: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const page = await loadPublicBox(slug);
  if (!page) return {};
  const tags = await getTranslations("BoxTags");
  const line = previewLine(page, (key) => tags(`discipline.${key}`));
  const description = page.profile.about?.slice(0, 200) || line;
  return {
    title: page.box.name,
    description,
    alternates: { canonical: `/b/${page.box.slug}` },
    openGraph: { title: page.box.name, description: line || description, type: "website", url: `/b/${page.box.slug}` },
    twitter: { card: "summary_large_image", title: page.box.name, description: line || description },
  };
}

/**
 * The public box page (ADR-142, plan §5a board 4): server-rendered so a
 * shared link previews well. Logged out, only «Σχετικά» is open (D2).
 */
export default async function PublicBoxRoute({ params }: Props) {
  const { slug } = await params;
  const page = await loadPublicBox(slug);
  if (!page) notFound();
  if (page.box.slug !== slug) permanentRedirect(`/b/${page.box.slug}`);
  return <PublicBoxView page={page} />;
}
