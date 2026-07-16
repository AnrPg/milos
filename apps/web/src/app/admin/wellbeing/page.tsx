
import { AdminWellbeing } from "@/components/admin-wellbeing";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default function AdminWellbeingPage() {
  
  return (
    <AuthGuard roles={["admin"]}>
      <AdminWellbeing />
    </AuthGuard>
  );
}
