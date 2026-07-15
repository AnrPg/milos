import { AuthGuard } from "@/components/auth-guard";
import { AdminCoaching } from "@/components/admin-coaching";

export const dynamic = "force-dynamic";

export default function AdminCoachingPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <AdminCoaching />
    </AuthGuard>
  );
}
