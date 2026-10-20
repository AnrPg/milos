import { AuthGuard } from "@/components/auth-guard";
import { GroupPage } from "@/components/community/GroupPage";

export const dynamic = "force-dynamic";

export default async function GroupRoute({ params }: { params: Promise<{ id: string; groupId: string }> }) {
  const { id, groupId } = await params;
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <GroupPage clubId={id} groupId={groupId} />
    </AuthGuard>
  );
}
