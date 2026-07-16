
import {useUiTranslations} from "@/i18n/ui";
import { AuthGuard } from "@/components/auth-guard";
import { AnalyticsMarketingHub } from "@/components/admin/AnalyticsMarketingHub";

export const dynamic = "force-dynamic";

export default function AdminMetricsPage() {
  const i18n = useUiTranslations();
  return (
    <AuthGuard roles={["admin"]}>
      <AnalyticsMarketingHub />
    </AuthGuard>
  );
}
