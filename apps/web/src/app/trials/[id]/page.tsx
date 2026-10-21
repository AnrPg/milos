import { AuthGuard } from "@/components/auth-guard";
import { TrialPage } from "@/components/trials/TrialPage";

export const dynamic = "force-dynamic";

export default async function TrialRoute({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <AuthGuard>
      <TrialPage trialId={id} />
    </AuthGuard>
  );
}
