import { AuthGuard } from "@/components/auth-guard";
import { ActivateBusinessPage } from "@/components/business/ActivateBusinessPage";

export const dynamic = "force-dynamic";

/** ADR-184: the activation link the Palee team sends a business owner. */
export default async function ActivateBusinessRoute({
  searchParams,
}: {
  searchParams: Promise<{ token?: string | string[] }>;
}) {
  const { token } = await searchParams;
  return (
    <AuthGuard>
      <ActivateBusinessPage token={typeof token === "string" ? token : ""} />
    </AuthGuard>
  );
}
