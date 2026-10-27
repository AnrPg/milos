"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useSyncExternalStore } from "react";

import { ApiError } from "@/api/client";
import { inspectInvitation } from "@/api/auth";
import { invitationSignUpPath, invitationTokenFromLocation, redeemInvitation } from "@/api/organizations";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError, semanticLabel } from "@/i18n/presentation";
import { membershipWorkspaceHref, rememberSelectedOrganization } from "@/lib/organization-slug";

/** Where the token waits while the person signs in, so it never sits in a URL. */
export const PENDING_INVITE_KEY = "palee_pending_invitation";

function readStored(): string {
  try {
    return window.sessionStorage.getItem(PENDING_INVITE_KEY) ?? "";
  } catch {
    return "";
  }
}

function store(token: string | null) {
  try {
    if (token) window.sessionStorage.setItem(PENDING_INVITE_KEY, token);
    else window.sessionStorage.removeItem(PENDING_INVITE_KEY);
  } catch {
    // Private mode: the link itself still works.
  }
}

/**
 * The token of this visit: the emailed link's `#token=` (or an older
 * `?token=`), else the one kept while signing in. The fragment is taken out
 * of the address bar once read.
 */
export function useInvitationToken(): string | null {
  const token = useSyncExternalStore(subscribeNever, readToken, () => null);
  useEffect(() => {
    const fromLink = invitationTokenFromLocation(window.location);
    if (!fromLink) return;
    store(fromLink);
    window.history.replaceState(null, "", window.location.pathname);
  }, []);
  return token;
}

function readToken(): string {
  return invitationTokenFromLocation(window.location) || readStored();
}

const subscribeNever = () => () => undefined;

const code = (error: unknown) => (error instanceof ApiError ? error.payload.code : undefined);

/** ADR-209: opens an invitation from its email: join with this account, or sign up / sign in first. */
export function InviteRedeemPage() {
  const t = useTranslations("Invites");
  const inviteT = useTranslations("InviteEmail");
  const uiT = useTranslations("Ui");
  const router = useRouter();
  const queryClient = useQueryClient();
  const { status, tokens, rotate, signOut } = useSession();
  const token = useInvitationToken();
  const invitation = useQuery({
    queryKey: ["invitation", token],
    enabled: Boolean(token),
    retry: false,
    queryFn: () => inspectInvitation(token!),
  });
  const join = useMutation({
    mutationFn: () => redeemInvitation(tokens!.access_token, token!),
    onSuccess: async (membership) => {
      store(null);
      rememberSelectedOrganization(membership.organization.slug);
      // Joining can change the account role, which invalidates the old token.
      await rotate().catch(() => undefined);
      await queryClient.invalidateQueries({ queryKey: ["organization-memberships"] });
      router.replace(membershipWorkspaceHref(membership));
    },
  });

  const shell = (content: React.ReactNode) => (
    <main className="flex min-h-[80dvh] items-center justify-center px-4 py-10" style={{ background: "var(--bg)" }}>
      <section className="w-full max-w-md rounded-[1.8rem] p-6 text-center" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        {content}
      </section>
    </main>
  );

  if (token === null || (token && invitation.isPending)) {
    return shell(<p className="text-sm" style={{ color: "var(--muted)" }}>{t("loading")}</p>);
  }

  if (!token || invitation.error) {
    const revoked = code(invitation.error) === "invitation_revoked";
    return shell(
      <>
        <h1 className="text-xl font-semibold" style={{ color: "var(--text)" }}>{revoked ? inviteT("revokedTitle") : inviteT("invalidTitle")}</h1>
        <p className="mt-2 text-sm leading-6" style={{ color: "var(--muted)" }}>{revoked ? inviteT("revokedBody") : inviteT("invalidBody")}</p>
        <Link href="/" className="mt-5 inline-block text-sm font-semibold underline" style={{ color: "var(--primary)" }}>{t("goHome")}</Link>
      </>,
    );
  }

  const data = invitation.data!;
  const roles = data.roles?.length ? data.roles : [data.role];
  const client = roles.every((role) => role === "member" || role === "athlete");
  const roleLabel = client ? t(`roles.${data.role === "athlete" ? "athlete" : "member"}`) : roles.map((role) => semanticLabel(role, uiT)).join(", ");
  const name = data.organization.name;
  const joinError = join.error;

  return shell(
    <>
      <p className="text-xs font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--primary)" }}>{t("youreInvited")}</p>
      <h1 className="mt-2 text-2xl font-semibold" style={{ color: "var(--text)" }}>{t("joinTitle", { organization: name })}</h1>
      <p className="mt-2 text-sm leading-6" style={{ color: "var(--muted)" }}>{t("joinBody", { role: roleLabel })}</p>
      {data.email_bound ? <p className="mt-2 text-xs leading-5" style={{ color: "var(--text-soft)" }}>{inviteT("boundNote")}</p> : null}

      {status === "authenticated" ? (
        <>
          <button
            type="button"
            disabled={join.isPending}
            onClick={() => join.mutate()}
            className="mt-6 w-full rounded-xl px-4 py-3 text-sm font-semibold disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--primary-contrast, var(--bg))" }}
          >
            {join.isPending ? t("joining") : t("joinCta", { organization: name })}
          </button>
          {joinError ? (
            <div className="mt-3 space-y-2">
              <ErrorNotice>
                {code(joinError) === "invitation_email_mismatch"
                  ? inviteT("mismatch")
                  : code(joinError) === "invitation_email_unverified"
                    ? inviteT("unverified")
                    : localizeError(joinError, uiT)}
              </ErrorNotice>
              {code(joinError) === "invitation_email_mismatch" ? (
                <button type="button" onClick={() => signOut()} className="text-sm font-semibold underline" style={{ color: "var(--primary)" }}>
                  {inviteT("signOut")}
                </button>
              ) : null}
            </div>
          ) : null}
        </>
      ) : status === "guest" ? (
        <div className="mt-6 grid gap-2">
          <Link
            href={`${invitationSignUpPath(data)}#token=${encodeURIComponent(token)}`}
            className="rounded-xl px-4 py-3 text-sm font-semibold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast, var(--bg))" }}
          >
            {t("createAccount")}
          </Link>
          <Link
            href={`/login?next=${encodeURIComponent("/invite")}`}
            className="rounded-xl px-4 py-3 text-sm font-semibold"
            style={{ border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {t("haveAccount")}
          </Link>
        </div>
      ) : null}
    </>,
  );
}
