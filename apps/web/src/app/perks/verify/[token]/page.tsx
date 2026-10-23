import type { Metadata } from "next";

import { PerkCheckPage } from "@/components/perks/PerkCheckPage";

export const dynamic = "force-dynamic";

// The link is the credential: never indexed, never previewed with its token.
export const metadata: Metadata = { robots: { index: false, follow: false }, referrer: "no-referrer" };

/** The store's check of a member's Palee QR (ADR-191): public, no login, signed and short-lived. */
export default async function PerkVerifyRoute({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  return <PerkCheckPage token={token} />;
}
