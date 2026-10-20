import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";

import { InvitePage } from "@/components/referrals/InvitePage";
import { loadReferralInvite } from "@/lib/referral-invite";

type Props = {
  params: Promise<{ code: string }>;
  searchParams: Promise<{ via?: string | string[]; event?: string | string[] }>;
};

export const dynamic = "force-dynamic";

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { code } = await params;
  const invite = await loadReferralInvite(code);
  if (!invite) return { robots: { index: false } };
  const t = await getTranslations("Referrals");
  const title = invite.inviter.nickname
    ? t("invite.title", { name: invite.inviter.nickname, box: invite.box.name })
    : t("invite.titleNoName", { box: invite.box.name });
  const description = t("invite.preview", { box: invite.box.name });
  return {
    title,
    description,
    robots: { index: false },
    openGraph: { title, description, type: "website", url: `/r/${invite.code}` },
    twitter: { card: "summary_large_image", title, description },
  };
}

/**
 * A member's invite (ADR-156, board 11 Q1): who invites, to which box, and
 * what the friend gets. Server-rendered so a shared link previews well; the
 * invite is kept on the device and credited once the friend is signed in.
 */
export default async function InviteRoute({ params, searchParams }: Props) {
  const { code } = await params;
  const query = await searchParams;
  const invite = await loadReferralInvite(code);
  if (!invite) notFound();
  const one = (value: string | string[] | undefined) => (typeof value === "string" ? value : null);
  return <InvitePage invite={invite} via={one(query.via)} eventId={one(query.event)} />;
}
