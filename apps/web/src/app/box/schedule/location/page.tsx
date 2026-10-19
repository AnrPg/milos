import { AuthGuard } from "@/components/auth-guard";
import { LocationPicker } from "@/components/member-app/box/schedule/LocationPicker";

export const dynamic = "force-dynamic";

export default function ScheduleLocationPage() {
  return (
    <AuthGuard roles={["member", "admin"]}>
      <LocationPicker />
    </AuthGuard>
  );
}
