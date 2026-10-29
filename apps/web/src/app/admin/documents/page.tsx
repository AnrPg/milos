import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { DocumentsConsole } from "@/components/documents/staff/DocumentsConsole";

export const dynamic = "force-dynamic";

/** Χρήστες › Έγγραφα (ADR-252, mockup s7 B): documents, signatures and health certificates. */
export default function AdminDocumentsPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <Suspense>
        <DocumentsConsole />
      </Suspense>
    </AuthGuard>
  );
}
