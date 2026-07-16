
import { AuthGuard } from "@/components/auth-guard";
import { AdminFinancePackageDetail } from "@/components/admin-finance-package-detail";

export const dynamic = "force-dynamic";

export default async function AdminFinancePackagePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  
  const { id } = await params;

  return (
    <AuthGuard roles={["admin"]}>
      <AdminFinancePackageDetail packageId={id} />
    </AuthGuard>
  );
}
