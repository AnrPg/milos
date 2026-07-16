
import {useUiTranslations} from "@/i18n/ui";
import { AdminDashboard } from "@/components/admin/AdminDashboard";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default function AdminPage() {
  const i18n = useUiTranslations();
  return (
    <AuthGuard roles={["admin"]}>
      <AdminDashboard />
    </AuthGuard>
  );
}
