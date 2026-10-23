import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { OrderPage } from "@/components/shop/OrderPage";

export const dynamic = "force-dynamic";

/** One shop order: QR, timeline and pickup (ADR-190); the «ready» notification and Συναλλαγές open it. */
export default async function BoxShopOrderRoute({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <AuthGuard roles={["member", "athlete"]} roleRedirects={{ admin: "/admin" }}>
      <Suspense>
        <OrderPage orderId={id} />
      </Suspense>
    </AuthGuard>
  );
}
