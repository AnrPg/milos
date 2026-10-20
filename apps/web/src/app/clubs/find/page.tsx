import { AuthGuard } from "@/components/auth-guard";
import { FindPage } from "@/components/community/FindPage";

export const dynamic = "force-dynamic";

export default function FindClubsRoute() {
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <FindPage />
    </AuthGuard>
  );
}
