import { AuthGuard } from "@/components/auth-guard";
import { ConnectedDevicesPage } from "@/components/check-in/ConnectedDevicesPage";

export const dynamic = "force-dynamic";

export default function ConnectedDevicesRoute() {
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <ConnectedDevicesPage />
    </AuthGuard>
  );
}
