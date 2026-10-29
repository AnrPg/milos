import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";

import { BoxScreenTv } from "@/components/box-screen/BoxScreenTv";

// ADR-253: the box screen. A TV browser opens it with no one signed in; it
// pairs with a code staff read out, then uses only its display token.
export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations("BoxScreens");
  return { title: t("pageTitle"), robots: { index: false, follow: false } };
}

export default function BoxScreenTvPage() {
  return <BoxScreenTv />;
}
