import { AuthGuard } from "@/components/auth-guard";
import { FollowRequestsPage } from "@/components/social/FollowRequestsPage";

export const dynamic = "force-dynamic";

export default function FollowRequestsRoute() {
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <FollowRequestsPage />
    </AuthGuard>
  );
}
