
import { AuthGuard } from "@/components/auth-guard";
import { WorkoutAuthoringModes } from "@/components/workouts/creation/WorkoutAuthoringModes";

export const dynamic = "force-dynamic";

export default function NewWorkoutPage() {
  
  return (
    <AuthGuard roles={["admin"]}>
      <WorkoutAuthoringModes />
    </AuthGuard>
  );
}
