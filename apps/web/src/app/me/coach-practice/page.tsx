import { AuthGuard } from "@/components/auth-guard";
import { StartCoachPractice } from "@/components/solo-coach/StartCoachPractice";

export const dynamic = "force-dynamic";

/** Εγώ › «Άνοιξε την πρακτική σου» (ADR-170): an account becomes an independent coach. */
export default function CoachPracticeRoute() {
  return (
    <AuthGuard>
      <StartCoachPractice />
    </AuthGuard>
  );
}
