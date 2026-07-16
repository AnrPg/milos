
import { AuthGuard } from "@/components/auth-guard";
import { AdminSettingsHub } from "@/components/admin-settings";

export const dynamic = "force-dynamic";

export default function AdminSettingsPage() {
  
  return (
    <AuthGuard roles={["admin"]}>
      <AdminSettingsHub />
    </AuthGuard>
  );
}
