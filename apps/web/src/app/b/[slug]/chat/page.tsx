import { AuthGuard } from "@/components/auth-guard";
import { BoxChat } from "@/components/trials/BoxChat";
import { parseChatTopic } from "@/components/trials/box-chat-links";

export const dynamic = "force-dynamic";

export default async function BoxChatRoute({
  params,
  searchParams,
}: {
  params: Promise<{ slug: string }>;
  searchParams: Promise<{ draft?: string | string[]; topic?: string | string[] }>;
}) {
  const { slug } = await params;
  const { draft, topic } = await searchParams;
  return (
    <AuthGuard>
      <BoxChat
        slug={slug}
        draft={typeof draft === "string" ? draft : null}
        topic={parseChatTopic(typeof topic === "string" ? topic : null)}
      />
    </AuthGuard>
  );
}
