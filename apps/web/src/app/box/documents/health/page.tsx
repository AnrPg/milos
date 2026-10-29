import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { MyHealthPage } from "@/components/documents/MyDocuments";

export const dynamic = "force-dynamic";

/** Box › Έγγραφα › Βεβαίωση υγείας: upload the certificate and its issue date (ADR-252 §5). */
export default function BoxHealthCertificateRoute() {
  return (
    <AuthGuard roles={["member", "athlete"]} roleRedirects={{ admin: "/admin/documents" }}>
      <Suspense>
        <MyHealthPage />
      </Suspense>
    </AuthGuard>
  );
}
