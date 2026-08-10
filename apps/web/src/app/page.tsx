import { AuthGuard } from "@/components/auth-guard";
import { Home } from "@/components/home";

export const dynamic = "force-dynamic";

export default function HomeRoute() {
  return (
    <AuthGuard roleRedirects={{ admin: "/admin" }}>
      <Home />
    </AuthGuard>
  );
}
