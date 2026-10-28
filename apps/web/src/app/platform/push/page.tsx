import { AuthGuard } from "@/components/auth-guard";
import { PlatformPushSettingsPage } from "@/components/platform/PlatformPushSettingsPage";

export const dynamic = "force-dynamic";

export default function PlatformPushRoute() {
  return (
    <AuthGuard>
      <PlatformPushSettingsPage />
    </AuthGuard>
  );
}
