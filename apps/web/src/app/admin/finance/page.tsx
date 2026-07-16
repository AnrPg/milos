
import { Suspense } from "react";

import { FinanceOperations } from "@/components/admin/finance/FinanceOperations";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default function AdminFinancePage() {
  
  return (
    <AuthGuard roles={["admin"]}>
      <Suspense>
        <FinanceOperations />
      </Suspense>
    </AuthGuard>
  );
}
