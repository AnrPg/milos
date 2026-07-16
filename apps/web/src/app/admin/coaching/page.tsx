
import {useUiTranslations} from "@/i18n/ui";
import { AuthGuard } from "@/components/auth-guard";
import { AdminCoaching } from "@/components/admin-coaching";

export const dynamic = "force-dynamic";

export default function AdminCoachingPage() {
  const i18n = useUiTranslations();
  return (
    <AuthGuard roles={["admin"]}>
      <AdminCoaching />
    </AuthGuard>
  );
}
