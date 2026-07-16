
import { AuthGuard } from "@/components/auth-guard";
import { FinanceDashboard } from "@/components/admin/finance/FinanceDashboard";

export const dynamic = "force-dynamic";

export default function AdminFinanceAnalyticsPage() {
  
  return (
    <AuthGuard roles={["admin"]}>
      <FinanceDashboard analyticsMode />
    </AuthGuard>
  );
}
