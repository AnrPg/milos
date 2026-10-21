import { AuthGuard } from "@/components/auth-guard";
import { ScanLanding } from "@/components/check-in/ScanLanding";

export const dynamic = "force-dynamic";

/** The printed poster's deep link (ADR-155 §5): only checks in to a booking in its window. */
export default async function PosterScanPage({ params }: { params: Promise<{ location: string; poster: string }> }) {
  const { location, poster } = await params;
  return (
    <AuthGuard>
      <ScanLanding locationId={location} code={poster} source="poster" />
    </AuthGuard>
  );
}
