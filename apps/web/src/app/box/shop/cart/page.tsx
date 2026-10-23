import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { CartPage } from "@/components/shop/CartPage";

export const dynamic = "force-dynamic";

/** Box › Κατάστημα › Καλάθι: cart and checkout on one screen (ADR-190). */
export default function BoxShopCartRoute() {
  return (
    <AuthGuard roles={["member", "athlete"]} roleRedirects={{ admin: "/admin" }}>
      <Suspense>
        <CartPage />
      </Suspense>
    </AuthGuard>
  );
}
