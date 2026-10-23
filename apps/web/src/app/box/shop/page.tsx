import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { ShopPage } from "@/components/shop/ShopPage";

export const dynamic = "force-dynamic";

/** Box › Κατάστημα (ADR-190); `?box=` opens another of the member's boxes, `?category=` a category. */
export default function BoxShopRoute() {
  return (
    <AuthGuard roles={["member", "athlete"]} roleRedirects={{ admin: "/admin" }}>
      <Suspense>
        <ShopPage />
      </Suspense>
    </AuthGuard>
  );
}
