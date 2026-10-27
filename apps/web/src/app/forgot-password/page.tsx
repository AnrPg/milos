import type { Metadata } from "next";

import { ForgotPassword } from "@/components/auth/ForgotPassword";

export const dynamic = "force-dynamic";

export const metadata: Metadata = { referrer: "no-referrer" };

export default function ForgotPasswordPage() {
  return <ForgotPassword />;
}
