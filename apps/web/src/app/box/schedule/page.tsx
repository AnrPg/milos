import { AuthGuard } from "@/components/auth-guard";
import { BoxSchedule } from "@/components/member-app/box/schedule/BoxSchedule";

export const dynamic = "force-dynamic";

export default async function SchedulePage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string>>;
}) {
  const params = await searchParams;
  return (
    <AuthGuard roles={["member", "admin"]}>
      <BoxSchedule initialOpenSlotId={params.open_slot ?? null} />
    </AuthGuard>
  );
}
