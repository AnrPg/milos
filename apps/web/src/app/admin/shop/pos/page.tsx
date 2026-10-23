import { AuthGuard } from "@/components/auth-guard";
import { PosDesk } from "@/components/shop/console/PosDesk";

export const dynamic = "force-dynamic";

export default function AdminShopPosPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <PosDesk />
    </AuthGuard>
  );
}
