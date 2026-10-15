import { AuthGuard } from "@/components/auth-guard";
import { VideosConsole } from "@/components/client/VideosConsole";

export const dynamic = "force-dynamic";

export default function VideosPage() {
  return (
    <AuthGuard roles={["member", "athlete"]}>
      <VideosConsole />
    </AuthGuard>
  );
}
