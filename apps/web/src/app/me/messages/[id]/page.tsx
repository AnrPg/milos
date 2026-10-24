import { AuthGuard } from "@/components/auth-guard";
import { ConversationScreen } from "@/components/conversations/ConversationScreen";

export const dynamic = "force-dynamic";

export default async function ConversationRoute({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <AuthGuard>
      <ConversationScreen conversationId={id} />
    </AuthGuard>
  );
}
