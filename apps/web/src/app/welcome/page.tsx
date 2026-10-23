import { AuthGuard } from "@/components/auth-guard";
import { FirstRun } from "@/components/first-run/FirstRun";

export const dynamic = "force-dynamic";

/** The member first-run after sign-up (ADR-183). */
export default function WelcomeRoute() {
  return (
    <AuthGuard>
      <FirstRun />
    </AuthGuard>
  );
}
