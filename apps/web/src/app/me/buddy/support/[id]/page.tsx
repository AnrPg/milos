import { AuthGuard } from "@/components/auth-guard";
import { BuddyScreen } from "@/components/buddy/BuddyScreen";
import { SupportRequestScreen } from "@/components/buddy/SupportRequestScreen";

export const dynamic = "force-dynamic";

export default async function SupportRequestRoute({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <BuddyScreen>
        <SupportRequestScreen requestId={id} />
      </BuddyScreen>
    </AuthGuard>
  );
}
