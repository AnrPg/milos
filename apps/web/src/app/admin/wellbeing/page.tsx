
import {useUiTranslations} from "@/i18n/ui";
import { AdminWellbeing } from "@/components/admin-wellbeing";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default function AdminWellbeingPage() {
  const i18n = useUiTranslations();
  return (
    <AuthGuard roles={["admin"]}>
      <AdminWellbeing />
    </AuthGuard>
  );
}
