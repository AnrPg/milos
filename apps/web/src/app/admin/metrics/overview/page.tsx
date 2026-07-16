
import { AdminAnalytics } from "@/components/admin-analytics";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default function AdminAnalyticsOverviewPage() {
  
  return (
    <AuthGuard roles={["admin"]}>
      <AdminAnalytics section="overview" />
    </AuthGuard>
  );
}
