import { AuthGuard } from "@/components/auth-guard";
import { EventsPage } from "@/components/events/EventsPage";

export const dynamic = "force-dynamic";

/** Events across your clubs; `?near=1` opens «Κοντά μου» (ADR-154). */
export default async function EventsRoute({ searchParams }: { searchParams: Promise<{ near?: string | string[] }> }) {
  const { near } = await searchParams;
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <EventsPage nearFirst={near === "1"} />
    </AuthGuard>
  );
}
