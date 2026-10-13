import { AuthGuard } from "@/components/auth-guard";
import { JournalWorkouts } from "@/components/client/JournalWorkouts";

export const dynamic = "force-dynamic";

export default function JournalPage() {
  return (
    <AuthGuard roles={["member", "athlete"]}>
      <JournalWorkouts />
    </AuthGuard>
  );
}
