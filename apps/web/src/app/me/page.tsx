import { AuthGuard } from "@/components/auth-guard";
import { MeHub } from "@/components/member-app/MeHub";

export const dynamic = "force-dynamic";

export default function MePage() {
  return (
    <AuthGuard roles={["member", "athlete"]} roleRedirects={{ admin: "/admin" }}>
      <MeHub />
    </AuthGuard>
  );
}
