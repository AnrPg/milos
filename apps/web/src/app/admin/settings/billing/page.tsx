import { AuthGuard } from "@/components/auth-guard";
import { FiscalIdentitySettings } from "@/components/fiscal/FiscalIdentitySettings";

export const dynamic = "force-dynamic";

// Mockup s1: Settings › «Στοιχεία τιμολόγησης» (ADR-240).
export default function AdminBillingDetailsPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <FiscalIdentitySettings />
    </AuthGuard>
  );
}
