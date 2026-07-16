
import { AuthGuard } from "@/components/auth-guard";
import { AnalyticsMarketingHub } from "@/components/admin/AnalyticsMarketingHub";

export const dynamic = "force-dynamic";

export default function AdminMetricsPage() {
  
  return (
    <AuthGuard roles={["admin"]}>
      <AnalyticsMarketingHub />
    </AuthGuard>
  );
}
