import { AuthGuard } from "@/components/auth-guard";
import { PlatformPartnerReportsPage } from "@/components/platform/PlatformPartnerReportsPage";

export const dynamic = "force-dynamic";

export default function PlatformPartnerReportsRoute() {
  return (
    <AuthGuard>
      <PlatformPartnerReportsPage />
    </AuthGuard>
  );
}
