import { AuthGuard } from "@/components/auth-guard";
import { BuddyPage } from "@/components/buddy/BuddyPage";
import { BuddyScreen } from "@/components/buddy/BuddyScreen";

export const dynamic = "force-dynamic";

export default function BuddyRoute() {
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <BuddyScreen>
        <BuddyPage />
      </BuddyScreen>
    </AuthGuard>
  );
}
