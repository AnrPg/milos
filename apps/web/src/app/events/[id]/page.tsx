import { AuthGuard } from "@/components/auth-guard";
import { EventPage } from "@/components/events/EventPage";

export const dynamic = "force-dynamic";

/**
 * An event (ADR-153); `?invite=` is a member's guest pass link, kept through
 * sign-in; `?ref=` is the member's referral code that came with it (ADR-156).
 */
export default async function EventRoute({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ invite?: string | string[]; ref?: string | string[] }>;
}) {
  const { id } = await params;
  const { invite, ref } = await searchParams;
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <EventPage
        eventId={id}
        invite={typeof invite === "string" && invite ? invite : null}
        referral={typeof ref === "string" && ref ? ref : null}
      />
    </AuthGuard>
  );
}
