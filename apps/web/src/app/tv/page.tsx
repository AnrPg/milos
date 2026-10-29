import type { Metadata } from "next";

import { BoxScreenTv } from "@/components/box-screen/BoxScreenTv";

// ADR-253: the box screen. A TV browser opens it with no one signed in; it
// pairs with a code staff read out, then uses only its display token.
export const metadata: Metadata = { title: "Palee TV", robots: { index: false, follow: false } };

export default function BoxScreenTvPage() {
  return <BoxScreenTv />;
}
