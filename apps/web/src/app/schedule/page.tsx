
import {getUiTranslations} from "@/i18n/ui-server";
import { AuthGuard } from "@/components/auth-guard";
import { ScheduleConsole } from "@/components/schedule/ScheduleConsole";

export const dynamic = "force-dynamic";

export default async function SchedulePage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string>>;
}) {
  const i18n = await getUiTranslations();
  const params = await searchParams;
  const initialOpenSlotId = params.open_slot ?? null;
  return (
    <AuthGuard roles={["member", "admin"]}>
      <ScheduleConsole initialOpenSlotId={initialOpenSlotId} />
    </AuthGuard>
  );
}
