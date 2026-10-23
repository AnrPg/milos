import { AuthGuard } from "@/components/auth-guard";
import { PerkPage } from "@/components/perks/PerkPage";

export const dynamic = "force-dynamic";

/** Εγώ › Πληρωμές › Προσφορές › a partner perk (ADR-191): claim it, its code or QR, terms. */
export default async function PerkRoute({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <PerkPage perkId={id} />
    </AuthGuard>
  );
}
