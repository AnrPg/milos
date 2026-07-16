
import {useUiTranslations} from "@/i18n/ui";
import { AuthGuard } from "@/components/auth-guard";
import { FinanceDashboard } from "@/components/admin/finance/FinanceDashboard";

export const dynamic = "force-dynamic";

export default function AdminFinanceAnalyticsPage() {
  const i18n = useUiTranslations();
  return (
    <AuthGuard roles={["admin"]}>
      <FinanceDashboard analyticsMode />
    </AuthGuard>
  );
}
