import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { PaymentReturnPage } from "@/components/payments/PaymentReturnPage";

export const dynamic = "force-dynamic";

/**
 * Where the payment provider sends the payer back (ADR-246/256): an app link
 * in the store apps, a page on the web. `?payment=`, `cancelled=1`, Viva's
 * `s`/`t`, and in dev/test the sandbox provider's `sandbox_checkout=`.
 */
export default function PayReturnRoute() {
  return (
    <AuthGuard>
      <Suspense>
        <PaymentReturnPage />
      </Suspense>
    </AuthGuard>
  );
}
