
import {useUiTranslations} from "@/i18n/ui";
import { AdminAnalytics } from "@/components/admin-analytics";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default function AdminAnalyticsOverviewPage() {
  const i18n = useUiTranslations();
  return (
    <AuthGuard roles={["admin"]}>
      <AdminAnalytics section="overview" />
    </AuthGuard>
  );
}
