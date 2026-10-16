import { AuthGuard } from "@/components/auth-guard";
import { MyClubsPage } from "@/components/community/MyClubsPage";

export const dynamic = "force-dynamic";

export default function MyClubsRoute() {
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <MyClubsPage />
    </AuthGuard>
  );
}
