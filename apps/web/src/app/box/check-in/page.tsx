import { AuthGuard } from "@/components/auth-guard";
import { MemberCheckIn } from "@/components/check-in/MemberCheckIn";

export const dynamic = "force-dynamic";

export default function BoxCheckInPage() {
  return (
    <AuthGuard roles={["member", "athlete"]}>
      <MemberCheckIn />
    </AuthGuard>
  );
}
