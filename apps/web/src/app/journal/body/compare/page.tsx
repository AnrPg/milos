import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { BodyScreen } from "@/components/body/BodyScreen";
import { ComparePage } from "@/components/body/ComparePage";

export const dynamic = "force-dynamic";

export default function BodyComparePage() {
  return (
    <AuthGuard roles={["member", "athlete"]}>
      <BodyScreen>
        <Suspense>
          <ComparePage />
        </Suspense>
      </BodyScreen>
    </AuthGuard>
  );
}
