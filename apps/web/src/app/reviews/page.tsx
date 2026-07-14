import { AuthGuard } from "@/components/auth-guard";
import { MyReviews } from "@/components/my-reviews";

export const dynamic = "force-dynamic";

export default function ReviewsPage() {
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <MyReviews />
    </AuthGuard>
  );
}
