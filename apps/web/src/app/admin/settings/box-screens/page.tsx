import { AuthGuard } from "@/components/auth-guard";
import { BoxScreensSettings } from "@/components/box-screen/BoxScreensSettings";

export const dynamic = "force-dynamic";

/** Ρυθμίσεις › Οθόνες box (ADR-253). */
export default function AdminBoxScreensPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <BoxScreensSettings />
    </AuthGuard>
  );
}
