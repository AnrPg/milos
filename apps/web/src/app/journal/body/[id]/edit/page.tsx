import { AuthGuard } from "@/components/auth-guard";
import { BodyScreen } from "@/components/body/BodyScreen";
import { EditSnapshot } from "@/components/body/SnapshotDetail";

export const dynamic = "force-dynamic";

export default async function EditBodySnapshotPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <AuthGuard roles={["member", "athlete"]}>
      <BodyScreen titleKey="editMeasure">
        <EditSnapshot snapshotId={id} />
      </BodyScreen>
    </AuthGuard>
  );
}
