import { AuthGuard } from "@/components/auth-guard";
import { HelpPage } from "@/components/member-app/me/HelpPage";

export const dynamic = "force-dynamic";

/** Εγώ › Βοήθεια & ξενάγηση (vision §7.11, ADR-196). */
export default function HelpRoute() {
  return (
    <AuthGuard>
      <HelpPage />
    </AuthGuard>
  );
}
