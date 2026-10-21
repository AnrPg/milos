import { AuthGuard } from "@/components/auth-guard";
import { ScanLanding } from "@/components/check-in/ScanLanding";

export const dynamic = "force-dynamic";

/** An NFC door tag's link (ADR-173): only checks in to a booking in its window. */
export default async function NfcTagScanPage({ params }: { params: Promise<{ location: string; tag: string }> }) {
  const { location, tag } = await params;
  return (
    <AuthGuard>
      <ScanLanding locationId={location} code={tag} source="nfc" />
    </AuthGuard>
  );
}
