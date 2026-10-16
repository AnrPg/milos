import { AuthGuard } from "@/components/auth-guard";
import { BoxHub } from "@/components/member-app/BoxHub";

export const dynamic = "force-dynamic";

export default function BoxPage() {
  return (
    <AuthGuard roles={["member", "athlete"]} roleRedirects={{ admin: "/admin" }}>
      <BoxHub />
    </AuthGuard>
  );
}
