
import { AuthGuard } from "@/components/auth-guard";
import { CheckInDesk } from "@/components/admin/facility/CheckInDesk";

export const dynamic = "force-dynamic";

export default function AdminCheckInPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <CheckInDesk />
    </AuthGuard>
  );
}
