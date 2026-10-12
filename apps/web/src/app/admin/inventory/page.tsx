import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { InventoryPage } from "@/components/inventory/InventoryPage";

export const dynamic = "force-dynamic";

export default function AdminInventoryPage() {
  return (
    <AuthGuard roles={["admin", "member", "athlete"]}>
      <Suspense>
        <InventoryPage />
      </Suspense>
    </AuthGuard>
  );
}
