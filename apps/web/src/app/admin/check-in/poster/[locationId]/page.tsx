import { AuthGuard } from "@/components/auth-guard";
import { PosterPage } from "@/components/check-in/PosterPage";

export const dynamic = "force-dynamic";

export default async function CheckInPosterPage({ params }: { params: Promise<{ locationId: string }> }) {
  const { locationId } = await params;
  return (
    <AuthGuard roles={["admin"]}>
      <PosterPage locationId={locationId} />
    </AuthGuard>
  );
}
