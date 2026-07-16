
import { AdminAnalytics } from "@/components/admin-analytics";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default function AdminEngagementAnalyticsPage() {
  
  return (
    <AuthGuard roles={["admin"]}>
      <AdminAnalytics section="engagement" />
    </AuthGuard>
  );
}
