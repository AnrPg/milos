import { AuthGuard } from "@/components/auth-guard";
import { JournalFlow } from "@/components/member-app/journal/JournalFlow";

export const dynamic = "force-dynamic";

export default function JournalFlowPage() {
  return (
    <AuthGuard roles={["member", "athlete"]}>
      <JournalFlow />
    </AuthGuard>
  );
}
