import { AuthGuard } from "@/components/auth-guard";
import { PlatformPartnerVerificationsPage } from "@/components/platform/PlatformPartnerVerificationsPage";

export const dynamic = "force-dynamic";

export default function PlatformPartnerVerificationsRoute() {
  return (
    <AuthGuard>
      <PlatformPartnerVerificationsPage />
    </AuthGuard>
  );
}
