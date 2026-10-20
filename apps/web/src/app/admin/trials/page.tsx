import { TrialQueue } from "@/components/admin/trials/TrialQueue";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default function AdminTrialsPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <TrialQueue />
    </AuthGuard>
  );
}
