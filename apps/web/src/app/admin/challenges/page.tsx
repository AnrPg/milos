
import { AuthGuard } from "@/components/auth-guard";
import { AdminChallenges } from "@/components/admin-challenges";

export const dynamic = "force-dynamic";

export default function AdminChallengesPage() {
  
  return (
    <AuthGuard roles={["admin"]}>
      <AdminChallenges />
    </AuthGuard>
  );
}
