import { AuthGuard } from "@/components/auth-guard";
import { BuddyScreen } from "@/components/buddy/BuddyScreen";
import { VouchRequestsPage } from "@/components/partner-verify/VouchRequestsPage";

export const dynamic = "force-dynamic";

/** The sponsor's requests to vouch (ADR-280), opened from the notification. */
export default function VouchRequestsRoute() {
  return (
    <AuthGuard>
      <BuddyScreen>
        <VouchRequestsPage />
      </BuddyScreen>
    </AuthGuard>
  );
}
