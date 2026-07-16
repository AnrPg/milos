
import { AuthGuard } from "@/components/auth-guard";
import { WorkoutCreationCanvas } from "@/components/workouts/creation/WorkoutCreationCanvas";

export const dynamic = "force-dynamic";

export default function NewWorkoutPage() {
  
  return (
    <AuthGuard roles={["admin"]}>
      <WorkoutCreationCanvas />
    </AuthGuard>
  );
}
