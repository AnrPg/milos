import { FinanceDashboard } from "@/components/admin/finance/FinanceDashboard";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default function AdminFinancePage() {
  return (
    <AuthGuard roles={["admin"]}>
      <FinanceDashboard />
    </AuthGuard>
  );
}
