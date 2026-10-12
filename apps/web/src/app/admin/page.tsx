import { StaffHome } from "@/components/admin/StaffHome";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default function AdminPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <StaffHome />
    </AuthGuard>
  );
}
