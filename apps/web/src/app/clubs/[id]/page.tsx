import { AuthGuard } from "@/components/auth-guard";
import { ClubPage } from "@/components/community/ClubPage";

export const dynamic = "force-dynamic";

export default async function ClubRoute({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <ClubPage clubId={id} />
    </AuthGuard>
  );
}
