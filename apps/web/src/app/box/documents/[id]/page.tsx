import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { MySignPage } from "@/components/documents/MyDocuments";

export const dynamic = "force-dynamic";

/** Box › Έγγραφα › read and sign one document (ADR-252). */
export default async function BoxDocumentRoute({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <AuthGuard roles={["member", "athlete"]} roleRedirects={{ admin: "/admin/documents" }}>
      <Suspense>
        <MySignPage templateId={id} />
      </Suspense>
    </AuthGuard>
  );
}
