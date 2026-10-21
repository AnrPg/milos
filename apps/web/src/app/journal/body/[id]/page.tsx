import { AuthGuard } from "@/components/auth-guard";
import { BodyScreen } from "@/components/body/BodyScreen";
import { SnapshotDetail } from "@/components/body/SnapshotDetail";

export const dynamic = "force-dynamic";

export default async function BodySnapshotPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <AuthGuard roles={["member", "athlete"]}>
      <BodyScreen>
        <SnapshotDetail snapshotId={id} />
      </BodyScreen>
    </AuthGuard>
  );
}
