import { AuthGuard } from "@/components/auth-guard";
import { ScanLanding } from "@/components/check-in/ScanLanding";

export const dynamic = "force-dynamic";

/** The store app's arrival reminder, tapped (ADR-173): only checks in to a booking in its window. */
export default async function ArrivalReminderPage({ params }: { params: Promise<{ location: string; token: string }> }) {
  const { location, token } = await params;
  return (
    <AuthGuard>
      <ScanLanding locationId={location} code={decodeURIComponent(token)} source="geofence" />
    </AuthGuard>
  );
}
