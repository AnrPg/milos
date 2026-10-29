import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { CollectFlow } from "@/components/admin/collect/CollectFlow";

export const dynamic = "force-dynamic";

// «Είσπραξη» with Tap to Pay on the staff phone (ADR-249, ADR-272).
export default function AdminCollectPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <Suspense>
        <CollectFlow />
      </Suspense>
    </AuthGuard>
  );
}
