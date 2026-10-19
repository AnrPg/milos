import { AuthGuard } from "@/components/auth-guard";
import { PublicPageEditor } from "@/components/admin/public-page/PublicPageEditor";

export const dynamic = "force-dynamic";

export default function AdminPublicPagePage() {
  return (
    <AuthGuard roles={["admin"]}>
      <PublicPageEditor />
    </AuthGuard>
  );
}
