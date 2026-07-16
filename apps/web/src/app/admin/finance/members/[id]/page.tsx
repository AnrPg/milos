
import {getUiTranslations} from "@/i18n/ui-server";
import { AuthGuard } from "@/components/auth-guard";
import { AdminFinanceMemberProfile } from "@/components/admin-finance-member-profile";

export const dynamic = "force-dynamic";

export default async function AdminFinanceMemberPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const i18n = await getUiTranslations();
  const { id } = await params;

  return (
    <AuthGuard roles={["admin"]}>
      <AdminFinanceMemberProfile userId={id} />
    </AuthGuard>
  );
}
