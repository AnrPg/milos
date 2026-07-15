import { AuthGuard } from "@/components/auth-guard";
import { ProfilePage } from "@/components/ProfilePage";

export const dynamic = "force-dynamic";

export default function ProfileRoute() {
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <ProfilePage />
    </AuthGuard>
  );
}
