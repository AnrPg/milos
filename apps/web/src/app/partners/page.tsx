import { AuthGuard } from "@/components/auth-guard";
import { PartnersPage } from "@/components/partners/PartnersPage";

export const dynamic = "force-dynamic";

/** Γύρω μου › «Συναθλητές κοντά σου» opens the public deck (ADR-280), full screen. */
export default function PartnersRoute() {
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <PartnersPage />
    </AuthGuard>
  );
}
