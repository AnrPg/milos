import { AuthGuard } from "@/components/auth-guard";
import { BuddyScreen } from "@/components/buddy/BuddyScreen";
import { VouchLinkLanding } from "@/components/partner-verify/VouchLinkLanding";

export const dynamic = "force-dynamic";

/** Where a sponsor link or QR lands: `/partners/vouch#token=…` (ADR-280). */
export default function VouchLinkRoute() {
  return (
    <AuthGuard>
      <BuddyScreen>
        <VouchLinkLanding />
      </BuddyScreen>
    </AuthGuard>
  );
}
