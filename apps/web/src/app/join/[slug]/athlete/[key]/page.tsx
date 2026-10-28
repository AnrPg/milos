import { JoinOrganizationPage } from "@/components/invites/JoinOrganizationPage";

export const dynamic = "force-dynamic";

/** ADR-216: the box's athlete join link; the key is what makes it the athlete link. */
export default async function AthleteJoinPage({ params }: { params: Promise<{ slug: string; key: string }> }) {
  const { slug, key } = await params;
  return <JoinOrganizationPage slug={slug} athleteKey={key} />;
}
