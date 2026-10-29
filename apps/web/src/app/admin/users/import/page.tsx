import { AuthGuard } from "@/components/auth-guard";
import { CsvImport } from "@/components/admin/imports/CsvImport";

export const dynamic = "force-dynamic";

// Staff › Χρήστες › Εισαγωγή (ADR-254, mockup s9 B).
export default function AdminUsersImportPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <CsvImport />
    </AuthGuard>
  );
}
