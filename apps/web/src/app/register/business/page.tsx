import { BusinessSignUp } from "@/components/business/BusinessSignUp";

export const dynamic = "force-dynamic";

/** ADR-184: «Επαγγελματικός λογαριασμός», a gym or coach in demo mode. */
export default function BusinessRegisterPage() {
  return <BusinessSignUp />;
}
