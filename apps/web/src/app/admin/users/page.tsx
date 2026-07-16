
import {useUiTranslations} from "@/i18n/ui";
import { AuthGuard } from "@/components/auth-guard";
import { AdminUsersDirectory } from "@/components/admin/users/AdminUsersDirectory";

export const dynamic = "force-dynamic";

export default function AdminUsersPage() {
  const i18n = useUiTranslations();
  return (
    <AuthGuard roles={["admin"]}>
      <AdminUsersDirectory />
    </AuthGuard>
  );
}
