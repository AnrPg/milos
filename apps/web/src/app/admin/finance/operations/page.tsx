import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { FinanceOperations } from "@/components/admin/finance/FinanceOperations";

export const dynamic = "force-dynamic";

export default function AdminFinanceOperationsPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <Suspense>
        <FinanceOperations />
      </Suspense>
    </AuthGuard>
  );
}
