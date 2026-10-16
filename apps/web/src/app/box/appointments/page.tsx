import { AuthGuard } from "@/components/auth-guard";
import { AppointmentsConsole } from "@/components/client/AppointmentsConsole";

export const dynamic = "force-dynamic";

export default function AppointmentsPage() {
  return (
    <AuthGuard roles={["member", "athlete"]}>
      <AppointmentsConsole />
    </AuthGuard>
  );
}
