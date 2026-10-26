import { AuthGuard } from "@/components/auth-guard";
import { SpacesSettings } from "@/components/spaces/SpacesSettings";

export const dynamic = "force-dynamic";

export default function AdminSpacesPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <SpacesSettings />
    </AuthGuard>
  );
}
