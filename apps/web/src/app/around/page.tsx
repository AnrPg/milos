import { AuthGuard } from "@/components/auth-guard";
import { AroundPage } from "@/components/around/AroundPage";

export const dynamic = "force-dynamic";

/** Αρχική › Γύρω μου (ADR-154); `?filter=<saved id>` opens a saved filter (the daily alert's link). */
export default function AroundRoute() {
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <AroundPage />
    </AuthGuard>
  );
}
