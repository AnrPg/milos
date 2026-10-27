import { InviteRedeemPage } from "@/components/invites/InviteRedeem";

export const dynamic = "force-dynamic";

/** ADR-209: where an emailed invitation opens (`/invite#token=…`). */
export default function InvitePage() {
  return <InviteRedeemPage />;
}
