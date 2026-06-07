import { AuthGuard } from "@/components/auth-guard";
import { LandingPage } from "@/components/landing-page";

export const dynamic = "force-dynamic";

export default function Home() {
  return (
    <AuthGuard>
      <LandingPage />
    </AuthGuard>
  );
}
