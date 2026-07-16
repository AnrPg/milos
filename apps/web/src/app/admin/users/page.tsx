
import { AuthGuard } from "@/components/auth-guard";
import { AdminUsersDirectory } from "@/components/admin/users/AdminUsersDirectory";

export const dynamic = "force-dynamic";

export default function AdminUsersPage() {
  
  return (
    <AuthGuard roles={["admin"]}>
      <AdminUsersDirectory />
    </AuthGuard>
  );
}
