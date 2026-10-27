import type { Metadata } from "next";

import { ResetPassword } from "@/components/auth/ResetPassword";

export const dynamic = "force-dynamic";

// ADR-206: the link's token never travels on as a referrer.
export const metadata: Metadata = { referrer: "no-referrer" };

export default function ResetPasswordPage() {
  return <ResetPassword />;
}
