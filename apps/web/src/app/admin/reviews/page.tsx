
import {useUiTranslations} from "@/i18n/ui";
import { AdminReviews } from "@/components/admin-reviews";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

export default function AdminReviewsPage() {
  const i18n = useUiTranslations();
  return (
    <AuthGuard roles={["admin"]}>
      <AdminReviews />
    </AuthGuard>
  );
}
