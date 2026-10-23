import { AuthGuard } from "@/components/auth-guard";
import { HostingConsole } from "@/components/events/HostingConsole";

export const dynamic = "force-dynamic";

const one = (value: string | string[] | undefined) => (typeof value === "string" ? value : null);

/** The organiser console (ADR-185): `?org=` the host's organisation, `?tab=`, `?event=`. */
export default async function EventsHostingRoute({
  searchParams,
}: {
  searchParams: Promise<{ org?: string | string[]; tab?: string | string[]; event?: string | string[] }>;
}) {
  const { org, tab, event } = await searchParams;
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <HostingConsole org={one(org)} tab={one(tab)} event={one(event)} />
    </AuthGuard>
  );
}
