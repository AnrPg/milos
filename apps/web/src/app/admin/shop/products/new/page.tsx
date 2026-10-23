import { AuthGuard } from "@/components/auth-guard";
import { ProductEditorPage } from "@/components/shop/console/ProductEditor";

export const dynamic = "force-dynamic";

export default function AdminShopNewProductPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <ProductEditorPage productId={null} />
    </AuthGuard>
  );
}
