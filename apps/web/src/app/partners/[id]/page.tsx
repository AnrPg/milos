import { AuthGuard } from "@/components/auth-guard";
import { BuddyScreen } from "@/components/buddy/BuddyScreen";
import { PartnerChat } from "@/components/partners/PartnerChat";

export const dynamic = "force-dynamic";

export default async function PartnerChatRoute({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <BuddyScreen>
        <PartnerChat matchId={id} />
      </BuddyScreen>
    </AuthGuard>
  );
}
