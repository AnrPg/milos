import { AuthGuard } from "@/components/auth-guard";
import { SquadPage } from "@/components/community/squads/SquadPage";

export const dynamic = "force-dynamic";

export default async function SquadRoute({ params }: { params: Promise<{ id: string; squadId: string }> }) {
  const { id, squadId } = await params;
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <SquadPage clubId={id} squadId={squadId} />
    </AuthGuard>
  );
}
