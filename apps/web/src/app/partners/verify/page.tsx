import { AuthGuard } from "@/components/auth-guard";
import { BuddyScreen } from "@/components/buddy/BuddyScreen";
import { PartnerVerifyPage } from "@/components/partner-verify/PartnerVerifyPage";

export const dynamic = "force-dynamic";

/** Συναθλητές › Επαλήθευση (ADR-280): any signed-in person, with or without a box. */
export default function PartnerVerifyRoute() {
  return (
    <AuthGuard>
      <BuddyScreen>
        <PartnerVerifyPage />
      </BuddyScreen>
    </AuthGuard>
  );
}
