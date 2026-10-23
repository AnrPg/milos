import { AuthGuard } from "@/components/auth-guard";
import { PasswordResetLogPage } from "@/components/password-resets/PasswordResetLogPage";

export const dynamic = "force-dynamic";

export default function PlatformPasswordResetLogRoute() {
  return (
    <AuthGuard>
      <PasswordResetLogPage />
    </AuthGuard>
  );
}
