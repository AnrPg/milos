
import {getUiTranslations} from "@/i18n/ui-server";
import { AuthGuard } from "@/components/auth-guard";
import { ScheduleConsole } from "@/components/schedule/ScheduleConsole";

export const dynamic = "force-dynamic";

export default async function AdminClassSchedulePage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string>>;
}) {
  const i18n = await getUiTranslations();
  const params = await searchParams;
  const initialOpenSlotId = params.open_slot ?? null;
  return (
    <AuthGuard roles={["admin"]}>
      <ScheduleConsole pageTitle={i18n("classesed1846a")} initialOpenSlotId={initialOpenSlotId} heroTimeoutMs={3000} />
    </AuthGuard>
  );
}
