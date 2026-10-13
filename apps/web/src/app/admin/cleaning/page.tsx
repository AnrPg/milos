import { AuthGuard } from "@/components/auth-guard";
import { CleaningLog } from "@/components/staff/CleaningLog";

export const dynamic = "force-dynamic";

export default function CleaningLogPage() {
  return (
    <AuthGuard roles={["admin", "member", "athlete"]}>
      <CleaningLog />
    </AuthGuard>
  );
}
