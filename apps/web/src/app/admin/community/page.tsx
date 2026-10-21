import { Suspense } from "react";

import { CommunityAdminPage } from "@/components/admin/community/CommunityAdminPage";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default function AdminCommunityRoute() {
  return (
    <AuthGuard roles={["admin", "member", "athlete"]}>
      <Suspense>
        <CommunityAdminPage />
      </Suspense>
    </AuthGuard>
  );
}
