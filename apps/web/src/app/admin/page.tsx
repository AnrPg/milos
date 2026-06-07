import { AdminHome } from "@/components/admin-home";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default function AdminPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <AdminHome />
    </AuthGuard>
  );
}
