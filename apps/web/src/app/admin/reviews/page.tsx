import { AdminReviews } from "@/components/admin-reviews";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default function AdminReviewsPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <AdminReviews />
    </AuthGuard>
  );
}
