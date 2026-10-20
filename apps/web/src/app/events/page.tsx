import { AuthGuard } from "@/components/auth-guard";
import { EventsPage } from "@/components/events/EventsPage";

export const dynamic = "force-dynamic";

export default function EventsRoute() {
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <EventsPage />
    </AuthGuard>
  );
}
