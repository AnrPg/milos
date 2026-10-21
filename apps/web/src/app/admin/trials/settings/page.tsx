import { TrialSettings } from "@/components/admin/trials/TrialSettings";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default function AdminTrialSettingsPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <TrialSettings />
    </AuthGuard>
  );
}
