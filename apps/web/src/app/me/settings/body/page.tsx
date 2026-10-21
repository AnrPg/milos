import { AuthGuard } from "@/components/auth-guard";
import { BodyScreen } from "@/components/body/BodyScreen";
import { BodySettingsPage } from "@/components/body/BodySettingsPage";

export const dynamic = "force-dynamic";

export default function BodySettingsRoute() {
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <BodyScreen>
        <BodySettingsPage />
      </BodyScreen>
    </AuthGuard>
  );
}
