import { AuthGuard } from "@/components/auth-guard";
import { AdminAppointments } from "@/components/staff/AdminAppointments";

export const dynamic = "force-dynamic";

export default function AdminAppointmentsPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <AdminAppointments />
    </AuthGuard>
  );
}
