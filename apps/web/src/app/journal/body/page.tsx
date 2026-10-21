import { AuthGuard } from "@/components/auth-guard";
import { BodyPage } from "@/components/body/BodyPage";

export const dynamic = "force-dynamic";

export default function JournalBodyPage() {
  return (
    <AuthGuard roles={["member", "athlete"]}>
      <BodyPage />
    </AuthGuard>
  );
}
