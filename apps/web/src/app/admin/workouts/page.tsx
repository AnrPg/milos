
import { AuthGuard } from "@/components/auth-guard";
import { WorkoutAdminConsole } from "@/components/workouts/WorkoutAdminConsole";

export const dynamic = "force-dynamic";

export default function AdminWorkoutsPage() {
  
  return (
    <AuthGuard roles={["admin"]}>
      <WorkoutAdminConsole />
    </AuthGuard>
  );
}
