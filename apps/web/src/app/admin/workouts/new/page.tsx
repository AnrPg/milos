
import {useUiTranslations} from "@/i18n/ui";
import { AuthGuard } from "@/components/auth-guard";
import { WorkoutCreationCanvas } from "@/components/workouts/creation/WorkoutCreationCanvas";

export const dynamic = "force-dynamic";

export default function NewWorkoutPage() {
  const i18n = useUiTranslations();
  return (
    <AuthGuard roles={["admin"]}>
      <WorkoutCreationCanvas />
    </AuthGuard>
  );
}
