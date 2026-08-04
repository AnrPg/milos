import { AuthGuard } from "@/components/auth-guard";
import { PlatformOrganizationsPage } from "@/components/platform/PlatformOrganizationsPage";

export const dynamic = "force-dynamic";

export default function PlatformOrganizationsRoute() {
  return (
    <AuthGuard>
      <PlatformOrganizationsPage />
    </AuthGuard>
  );
}
