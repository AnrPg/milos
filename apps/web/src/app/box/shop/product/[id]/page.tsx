import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { ProductPage } from "@/components/shop/ProductPage";

export const dynamic = "force-dynamic";

/** A product of the box shop; `?post=` is the club post it was opened from (ADR-192 attribution). */
export default async function BoxShopProductRoute({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <AuthGuard roles={["member", "athlete"]} roleRedirects={{ admin: "/admin" }}>
      <Suspense>
        <ProductPage productId={id} />
      </Suspense>
    </AuthGuard>
  );
}
