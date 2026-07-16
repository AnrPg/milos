
import {useUiTranslations} from "@/i18n/ui";
import { AuthGuard } from "@/components/auth-guard";
import { AdminChallenges } from "@/components/admin-challenges";

export const dynamic = "force-dynamic";

export default function AdminChallengesPage() {
  const i18n = useUiTranslations();
  return (
    <AuthGuard roles={["admin"]}>
      <AdminChallenges />
    </AuthGuard>
  );
}
