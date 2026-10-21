import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";

import { SupportLinesPage } from "@/components/buddy/SupportLinesPage";

export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations("Buddy");
  return { title: t("linesTitle"), robots: { index: false } };
}

export default function SupportLinesRoute() {
  return <SupportLinesPage />;
}
