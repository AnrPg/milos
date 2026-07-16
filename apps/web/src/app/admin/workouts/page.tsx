
import {useUiTranslations} from "@/i18n/ui";
import { AuthGuard } from "@/components/auth-guard";
import { WorkoutAdminConsole } from "@/components/workouts/WorkoutAdminConsole";

export const dynamic = "force-dynamic";

export default function AdminWorkoutsPage() {
  const i18n = useUiTranslations();
  return (
    <AuthGuard roles={["admin"]}>
      <WorkoutAdminConsole />
    </AuthGuard>
  );
}
