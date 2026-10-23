import { Suspense } from "react";

import { BillingPage } from "@/components/billing/BillingPage";

export const dynamic = "force-dynamic";

/** Εγώ › Πληρωμές & αποδείξεις; `?box=` opens one provider, `?company=` a corporate plan link. */
export default function PaymentsRoute() {
  return (
    <Suspense>
      <BillingPage />
    </Suspense>
  );
}
