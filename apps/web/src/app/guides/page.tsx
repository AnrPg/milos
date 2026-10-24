import { AuthGuard } from "@/components/auth-guard";
import { GuidesPage } from "@/components/guides/GuidesPage";

export const dynamic = "force-dynamic";

/** ADR-193: every walkthrough this person can open, with where they got to. */
export default function GuidesRoute() {
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <GuidesPage />
    </AuthGuard>
  );
}
