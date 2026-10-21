import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { AtlasScreen } from "@/components/anatomy/atlas/AtlasScreen";

export const dynamic = "force-dynamic";

// Ημερολόγιο › Πρόοδος › Άτλαντας (ADR-164).
export default function AtlasPage() {
  return (
    <AuthGuard roles={["member", "athlete"]}>
      <Suspense fallback={null}>
        <AtlasScreen />
      </Suspense>
    </AuthGuard>
  );
}
