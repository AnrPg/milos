import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { PasswordResetsPage } from "@/components/password-resets/PasswordResetsPage";

export const dynamic = "force-dynamic";

export default function PasswordResetsRoute() {
  return (
    <AuthGuard>
      <Suspense>
        <PasswordResetsPage />
      </Suspense>
    </AuthGuard>
  );
}
