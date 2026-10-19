import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { ConnectionsPage } from "@/components/social/ConnectionsPage";

export const dynamic = "force-dynamic";

export default function ConnectionsRoute() {
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <Suspense>
        <ConnectionsPage />
      </Suspense>
    </AuthGuard>
  );
}
