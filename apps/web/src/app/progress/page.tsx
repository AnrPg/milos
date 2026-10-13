import { AuthGuard } from "@/components/auth-guard";
import { ProgressConsole } from "@/components/client/ProgressConsole";

export const dynamic = "force-dynamic";

export default function ProgressPage() {
  return (
    <AuthGuard roles={["member", "athlete"]}>
      <ProgressConsole />
    </AuthGuard>
  );
}
