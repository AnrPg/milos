import { AuthGuard } from "@/components/auth-guard";
import { AdminContent } from "@/components/staff/AdminContent";

export const dynamic = "force-dynamic";

export default function AdminContentPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <AdminContent />
    </AuthGuard>
  );
}
