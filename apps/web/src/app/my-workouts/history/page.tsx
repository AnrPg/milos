import { AuthGuard } from "@/components/auth-guard";
import { WorkoutHistory } from "@/components/client/WorkoutHistory";

export const dynamic = "force-dynamic";

export default function WorkoutHistoryPage() {
  return (
    <AuthGuard roles={["member", "athlete"]}>
      <WorkoutHistory />
    </AuthGuard>
  );
}
