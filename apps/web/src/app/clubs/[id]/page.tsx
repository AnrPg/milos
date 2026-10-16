import { AuthGuard } from "@/components/auth-guard";
import { ClubPage } from "@/components/community/ClubPage";

export const dynamic = "force-dynamic";

export default async function ClubRoute({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ channel?: string | string[] }>;
}) {
  const { id } = await params;
  const { channel } = await searchParams;
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <ClubPage clubId={id} channelId={typeof channel === "string" ? channel : null} />
    </AuthGuard>
  );
}
