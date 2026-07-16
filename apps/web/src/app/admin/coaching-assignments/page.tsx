
import {getUiTranslations} from "@/i18n/ui-server";
import { AuthGuard } from "@/components/auth-guard";
import { AssignedWorkoutsConsole } from "@/components/workouts/AssignedWorkoutsConsole";

export const dynamic = "force-dynamic";

export default async function AdminCoachingAssignmentsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string>>;
}) {
  const i18n = await getUiTranslations();
  const params = await searchParams;
  const initialOpenAssignmentId = params.open_assignment ?? null;
  return (
    <AuthGuard roles={["admin"]}>
      <AssignedWorkoutsConsole
        pageTitle={i18n("personalCoaching6accdcd")}
        initialOpenAssignmentId={initialOpenAssignmentId}
      />
    </AuthGuard>
  );
}
