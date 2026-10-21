import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { ReferralsPage } from "@/components/referrals/ReferralsPage";

export const dynamic = "force-dynamic";

/** Εγώ › Φέρε φίλο (ADR-156); `?box=` opens one of the member's boxes. */
export default function ReferralsRoute() {
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <Suspense>
        <ReferralsPage />
      </Suspense>
    </AuthGuard>
  );
}
