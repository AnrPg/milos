import { AuthGuard } from "@/components/auth-guard";
import { SetupRecipes } from "@/components/admin/setup/SetupRecipes";

export const dynamic = "force-dynamic";

// First setup: «Τι είδους box έχεις;» (ADR-255, mockup s10 A).
export default function AdminSetupPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <SetupRecipes />
    </AuthGuard>
  );
}
