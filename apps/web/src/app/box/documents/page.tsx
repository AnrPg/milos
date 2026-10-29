import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { MyDocuments } from "@/components/documents/MyDocuments";

export const dynamic = "force-dynamic";

/** Box › Έγγραφα (ADR-252, mockup s7): what to sign, the health certificate, past signatures. */
export default function BoxDocumentsRoute() {
  return (
    <AuthGuard roles={["member", "athlete"]} roleRedirects={{ admin: "/admin/documents" }}>
      <Suspense>
        <MyDocuments />
      </Suspense>
    </AuthGuard>
  );
}
