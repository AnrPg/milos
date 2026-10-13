import { AuthGuard } from "@/components/auth-guard";
import { CoachingConsole } from "@/components/client/CoachingConsole";

export const dynamic = "force-dynamic";

export default function CoachingPage() {
  return (
    <AuthGuard roles={["member", "athlete"]}>
      <CoachingConsole />
    </AuthGuard>
  );
}
