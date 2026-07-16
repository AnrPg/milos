
import {useUiTranslations} from "@/i18n/ui";
import { AuthGuard } from "@/components/auth-guard";
import { AdminSettingsHub } from "@/components/admin-settings";

export const dynamic = "force-dynamic";

export default function AdminSettingsPage() {
  const i18n = useUiTranslations();
  return (
    <AuthGuard roles={["admin"]}>
      <AdminSettingsHub />
    </AuthGuard>
  );
}
