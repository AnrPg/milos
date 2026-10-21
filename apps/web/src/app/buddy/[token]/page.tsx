import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";

import { BuddyInviteLanding } from "@/components/buddy/BuddyInviteLanding";

type Props = { params: Promise<{ token: string }> };

export const dynamic = "force-dynamic";

export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations("Buddy");
  return { title: t("inviteHeading"), description: t("whatOnly"), robots: { index: false } };
}

/** A shared buddy link (ADR-160): what a buddy is, who invites, then sign in and accept. */
export default async function BuddyInviteRoute({ params }: Props) {
  const { token } = await params;
  return <BuddyInviteLanding inviteToken={token} />;
}
