import { AuthGuard } from "@/components/auth-guard";
import { InterestsSettingsPage } from "@/components/interests/InterestsSettingsPage";

export const dynamic = "force-dynamic";

/** Εγώ › «Τι κάνεις» (ADR-183). */
export default function InterestsSettingsRoute() {
  return (
    <AuthGuard>
      <InterestsSettingsPage />
    </AuthGuard>
  );
}
