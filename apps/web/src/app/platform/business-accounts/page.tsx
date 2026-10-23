import { AuthGuard } from "@/components/auth-guard";
import { PlatformBusinessAccountsPage } from "@/components/platform/PlatformBusinessAccountsPage";

export const dynamic = "force-dynamic";

export default function PlatformBusinessAccountsRoute() {
  return (
    <AuthGuard>
      <PlatformBusinessAccountsPage />
    </AuthGuard>
  );
}
