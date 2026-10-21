import { AuthGuard } from "@/components/auth-guard";
import { ScanLanding } from "@/components/check-in/ScanLanding";

export const dynamic = "force-dynamic";

/** The door QR's deep link (ADR-155): signed out, sign in and come back here. */
export default async function DoorScanPage({ params }: { params: Promise<{ location: string; code: string }> }) {
  const { location, code } = await params;
  return (
    <AuthGuard>
      <ScanLanding locationId={location} code={code} source="door" />
    </AuthGuard>
  );
}
