
import {getUiTranslations} from "@/i18n/ui-server";
import { AuthGuard } from "@/components/auth-guard";
import { AssignWorkoutForm } from "@/components/workouts/AssignWorkoutForm";

export const dynamic = "force-dynamic";

export default async function AssignWorkoutPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const i18n = await getUiTranslations();
  const { id } = await params;

  return (
    <AuthGuard roles={["admin"]}>
      <AssignWorkoutForm workoutId={id} />
    </AuthGuard>
  );
}
