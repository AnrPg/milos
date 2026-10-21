import { AuthGuard } from "@/components/auth-guard";
import { BuddyChat } from "@/components/buddy/BuddyChat";
import { BuddyScreen } from "@/components/buddy/BuddyScreen";

export const dynamic = "force-dynamic";

export default async function BuddyChatRoute({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <BuddyScreen>
        <BuddyChat linkId={id} />
      </BuddyScreen>
    </AuthGuard>
  );
}
