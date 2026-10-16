import { AuthGuard } from "@/components/auth-guard";
import { MyPostsPage } from "@/components/community/MyPostsPage";

export const dynamic = "force-dynamic";

export default function MyPostsRoute() {
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <MyPostsPage />
    </AuthGuard>
  );
}
