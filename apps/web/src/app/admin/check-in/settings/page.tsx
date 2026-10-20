import { AuthGuard } from "@/components/auth-guard";
import { CheckInSettings } from "@/components/check-in/CheckInSettings";

export const dynamic = "force-dynamic";

export default function AdminCheckInSettingsPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <CheckInSettings />
    </AuthGuard>
  );
}
