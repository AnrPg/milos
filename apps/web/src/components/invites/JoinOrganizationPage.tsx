"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import Link from "next/link";
import { useRouter } from "next/navigation";

import { ApiError } from "@/api/client";
import { inspectJoinLink, joinOrganization, joinPath } from "@/api/organizations";
import { useSession } from "@/components/session-provider";
import { localizeError } from "@/i18n/presentation";
import { membershipWorkspaceHref, rememberSelectedOrganization } from "@/lib/organization-slug";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

export function JoinOrganizationPage({ slug, athleteKey }: { slug: string; athleteKey?: string }) {
  const t = useTranslations("Invites");
  const uiT = useTranslations("Ui");
  const router = useRouter();
  const queryClient = useQueryClient();
  const { status, tokens, rotate } = useSession();
  const target = { slug, athleteKey };
  const link = useQuery({
    queryKey: ["public-join-link", slug, athleteKey ?? null],
    queryFn: () => inspectJoinLink(target),
    retry: false,
  });
  const join = useMutation({
    mutationFn: () => joinOrganization(tokens!.access_token, target),
    onSuccess: async (membership) => {
      rememberSelectedOrganization(membership.organization.slug);
      // Joining can change the account role, which invalidates the old token.
      await rotate().catch(() => undefined);
      await queryClient.invalidateQueries({ queryKey: ["organization-memberships"] });
      router.replace(membershipWorkspaceHref(membership));
    },
  });

  const next = joinPath(target);
  const name = link.data?.settings?.brand_name || link.data?.organization.name;
  const role = link.data?.role === "athlete" ? "athlete" : "member";

  return (
    <main className="flex min-h-[80dvh] items-center justify-center px-4 py-10" style={{ background: "var(--bg)" }}>
      <section className="w-full max-w-md rounded-[1.8rem] p-6 text-center" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        {link.isPending ? (
          <p className="text-sm" style={{ color: "var(--muted)" }}>{t("loading")}</p>
        ) : link.error ? (
          <>
            <h1 className="text-xl font-semibold" style={{ color: "var(--text)" }}>{t("joinUnavailableTitle")}</h1>
            <p className="mt-2 text-sm leading-6" style={{ color: "var(--muted)" }}>{t("joinUnavailable")}</p>
            <Link href="/" className="mt-5 inline-block text-sm font-semibold underline" style={{ color: "var(--primary)" }}>{t("goHome")}</Link>
          </>
        ) : (
          <>
            {link.data?.settings?.brand_logo_url ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={link.data.settings.brand_logo_url} alt="" className="mx-auto mb-4 h-14 w-14 rounded-2xl object-cover" />
            ) : null}
            <p className="text-xs font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--primary)" }}>{t("youreInvited")}</p>
            <h1 className="mt-2 text-2xl font-semibold" style={{ color: "var(--text)" }}>{t("joinTitle", { organization: name ?? slug })}</h1>
            <p className="mt-2 text-sm leading-6" style={{ color: "var(--muted)" }}>
              {t("joinBody", { role: t(`roles.${role}`) })}
            </p>

            {status === "authenticated" ? (
              <>
                <button
                  type="button"
                  disabled={join.isPending}
                  onClick={() => join.mutate()}
                  className="mt-6 w-full rounded-xl px-4 py-3 text-sm font-semibold disabled:opacity-50"
                  style={{ background: "var(--primary)", color: "var(--primary-contrast, var(--bg))" }}
                >
                  {join.isPending ? t("joining") : t("joinCta", { organization: name ?? slug })}
                </button>
                {join.error ? (
                  <ErrorNotice className="mt-3">
                    {join.error instanceof ApiError && join.error.payload.code === "membership_unavailable"
                      ? t("membershipUnavailable")
                      : localizeError(join.error, uiT)}
                  </ErrorNotice>
                ) : null}
              </>
            ) : status === "guest" ? (
              <div className="mt-6 grid gap-2">
                <Link
                  href={`/register?next=${encodeURIComponent(next)}&role=${role}`}
                  className="rounded-xl px-4 py-3 text-sm font-semibold"
                  style={{ background: "var(--primary)", color: "var(--primary-contrast, var(--bg))" }}
                >
                  {t("createAccount")}
                </Link>
                <Link
                  href={`/login?next=${encodeURIComponent(next)}`}
                  className="rounded-xl px-4 py-3 text-sm font-semibold"
                  style={{ border: "1px solid var(--border)", color: "var(--text)" }}
                >
                  {t("haveAccount")}
                </Link>
              </div>
            ) : null}
          </>
        )}
      </section>
    </main>
  );
}
