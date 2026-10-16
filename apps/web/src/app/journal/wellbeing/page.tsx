import { AuthGuard } from "@/components/auth-guard";
import { MyWellbeing } from "@/components/my-wellbeing";

export const dynamic = "force-dynamic";

export default function WellbeingPage() {
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <MyWellbeing />
    </AuthGuard>
  );
}
