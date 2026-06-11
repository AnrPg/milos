import { AuthGuard } from "@/components/auth-guard";
import { ScheduleConsole } from "@/components/schedule/ScheduleConsole";

export const dynamic = "force-dynamic";

export default async function AdminClassSchedulePage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string>>;
}) {
  const params = await searchParams;
  const initialOpenSlotId = params.open_slot ?? null;
  return (
    <AuthGuard roles={["admin"]}>
      <ScheduleConsole pageTitle="Class Schedule" initialOpenSlotId={initialOpenSlotId} />
    </AuthGuard>
  );
}
