import { AuthGuard } from "@/components/auth-guard";
import { AdminUserProfile } from "@/components/admin/users/AdminUserProfile";

export const dynamic = "force-dynamic";

export default async function AdminUserProfilePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;

  return (
    <AuthGuard roles={["admin"]}>
      <AdminUserProfile userId={id} />
    </AuthGuard>
  );
}
