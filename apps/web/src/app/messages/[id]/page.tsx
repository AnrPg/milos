import { AuthGuard } from "@/components/auth-guard";
import { ConversationScreen } from "@/components/conversations/ConversationScreen";

export const dynamic = "force-dynamic";

/** One person conversation (ADR-193 §3) inside the one inbox (ADR-196); `/me/messages/:id` redirects here. */
export default async function ConversationRoute({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <AuthGuard>
      <ConversationScreen conversationId={id} />
    </AuthGuard>
  );
}
