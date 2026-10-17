import { AuthGuard } from "@/components/auth-guard";
import { SharingPage } from "@/components/member-app/me/SharingPage";

export const dynamic = "force-dynamic";

export default function SharingRoute() {
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <SharingPage />
    </AuthGuard>
  );
}
