import { StaffEventPage } from "@/components/admin/community/StaffEventPage";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default async function AdminCommunityEventRoute({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <AuthGuard roles={["admin"]}>
      <StaffEventPage eventId={id} />
    </AuthGuard>
  );
}
