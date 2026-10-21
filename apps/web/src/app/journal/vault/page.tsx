import { AuthGuard } from "@/components/auth-guard";
import { AccountVault } from "@/components/client/AccountVault";

export const dynamic = "force-dynamic";

export default function JournalPage() {
  return (
    <AuthGuard roles={["member", "athlete"]}>
      <AccountVault />
    </AuthGuard>
  );
}
