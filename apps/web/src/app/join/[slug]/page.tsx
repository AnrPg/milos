import { JoinOrganizationPage } from "@/components/invites/JoinOrganizationPage";

export const dynamic = "force-dynamic";

export default async function JoinPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  return <JoinOrganizationPage slug={slug} />;
}
