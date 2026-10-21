import { AuthGuard } from "@/components/auth-guard";
import { PlatformPlansPage } from "@/components/platform/PlatformPlansPage";

export const dynamic = "force-dynamic";

export default function PlatformPlansRoute() {
  return (
    <AuthGuard>
      <PlatformPlansPage />
    </AuthGuard>
  );
}
