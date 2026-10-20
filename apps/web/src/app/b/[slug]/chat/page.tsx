import { AuthGuard } from "@/components/auth-guard";
import { BoxChat } from "@/components/trials/BoxChat";

export const dynamic = "force-dynamic";

export default async function BoxChatRoute({
  params,
  searchParams,
}: {
  params: Promise<{ slug: string }>;
  searchParams: Promise<{ draft?: string | string[] }>;
}) {
  const { slug } = await params;
  const { draft } = await searchParams;
  return (
    <AuthGuard>
      <BoxChat slug={slug} draft={typeof draft === "string" ? draft : null} />
    </AuthGuard>
  );
}
