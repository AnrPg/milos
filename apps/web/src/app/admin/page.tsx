
import { AdminDashboard } from "@/components/admin/AdminDashboard";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default function AdminPage() {
  
  return (
    <AuthGuard roles={["admin"]}>
      <AdminDashboard />
    </AuthGuard>
  );
}
