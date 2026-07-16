
import { AdminAnalytics } from "@/components/admin-analytics";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default function AdminTrainingAnalyticsPage() {
  
  return (
    <AuthGuard roles={["admin"]}>
      <AdminAnalytics section="training" />
    </AuthGuard>
  );
}
