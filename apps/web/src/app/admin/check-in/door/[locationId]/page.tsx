import { AuthGuard } from "@/components/auth-guard";
import { DoorKiosk } from "@/components/check-in/DoorKiosk";

export const dynamic = "force-dynamic";

export default async function DoorKioskPage({ params }: { params: Promise<{ locationId: string }> }) {
  const { locationId } = await params;
  return (
    <AuthGuard roles={["admin"]}>
      <DoorKiosk locationId={locationId} />
    </AuthGuard>
  );
}
