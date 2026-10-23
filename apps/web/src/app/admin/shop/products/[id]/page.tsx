import { AuthGuard } from "@/components/auth-guard";
import { ProductEditorPage } from "@/components/shop/console/ProductEditor";

export const dynamic = "force-dynamic";

export default async function AdminShopProductPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <AuthGuard roles={["admin"]}>
      <ProductEditorPage productId={id} />
    </AuthGuard>
  );
}
