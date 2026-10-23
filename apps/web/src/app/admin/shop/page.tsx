import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { ShopConsole } from "@/components/shop/console/ShopConsole";

export const dynamic = "force-dynamic";

export default function AdminShopPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <Suspense>
        <ShopConsole />
      </Suspense>
    </AuthGuard>
  );
}
