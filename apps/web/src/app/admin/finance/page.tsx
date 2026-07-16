
import {useUiTranslations} from "@/i18n/ui";
import { Suspense } from "react";

import { FinanceOperations } from "@/components/admin/finance/FinanceOperations";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default function AdminFinancePage() {
  const i18n = useUiTranslations();
  return (
    <AuthGuard roles={["admin"]}>
      <Suspense>
        <FinanceOperations />
      </Suspense>
    </AuthGuard>
  );
}
