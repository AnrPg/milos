"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { activationTokenFrom, inspectActivation, redeemActivation } from "@/api/business-accounts";
import { AuthNotice, AuthShell, primaryButtonClass, primaryButtonStyle } from "@/components/auth/AuthShell";
import { useSession } from "@/components/session-provider";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { rememberSelectedOrganization } from "@/lib/organization-slug";
import { setView } from "@/lib/view-mode";

/**
 * ADR-184: the activation link. Opened while signed in as the account it
 * names, it shows the business and what activation does (demo data removed,
 * the owner's own setup kept, everything goes live), then activates it.
 * ADR-205: the emailed link carries the token in the fragment
 * (`#token=…`), which only the browser sees; older links use `?token=…`.
 */
export function ActivateBusinessPage({ token: queryToken }: { token: string }) {
  const [token] = useState(() =>
    activationTokenFrom(queryToken, typeof window === "undefined" ? "" : window.location.hash),
  );
  const t = useTranslations("Business");
  const i18n = useUiTranslations();
  const router = useRouter();
  const queryClient = useQueryClient();
  const { tokens, currentUser } = useSession();
  const access = tokens?.access_token ?? null;

  const preview = useQuery({
    queryKey: ["business-activation"],
    enabled: Boolean(access && token),
    queryFn: () => inspectActivation(access!, token),
    retry: false,
  });

  const redeem = useMutation({
    mutationFn: () => redeemActivation(access!, token),
    onSuccess: (result) => {
      rememberSelectedOrganization(result.organization.slug);
      setView("staff");
      void queryClient.invalidateQueries();
    },
  });

  if (redeem.data) {
    const slug = redeem.data.organization.slug;
    return (
      <AuthShell title={t("activate.doneTitle")}>
        <div className="space-y-5">
          <AuthNotice tone="success">{t("activate.done", { name: redeem.data.organization.name })}</AuthNotice>
          {/* ADR-221: live is not findable; the page has to be published too. */}
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("activate.publishNext")}</p>
          <button
            type="button"
            className={primaryButtonClass}
            style={primaryButtonStyle}
            onClick={() => router.replace(`/org/${slug}/admin/public-page`)}
          >
            {t("activate.openPublicPage")}
          </button>
          <button
            type="button"
            className="min-h-11 w-full rounded-full text-sm font-semibold"
            style={{ background: "var(--border)", color: "var(--text-soft)" }}
            onClick={() => router.replace(`/org/${slug}/admin`)}
          >
            {t("signUp.openConsole")}
          </button>
        </div>
      </AuthShell>
    );
  }

  if (!token || preview.isError) {
    return (
      <AuthShell title={t("activate.title")}>
        <div className="space-y-4 text-sm" style={{ color: "var(--text-soft)" }}>
          <AuthNotice>{t("activate.invalid")}</AuthNotice>
          {currentUser ? <p>{t("activate.signedInAs", { name: currentUser.nickname })}</p> : null}
        </div>
      </AuthShell>
    );
  }

  if (!preview.data) {
    return (
      <AuthShell title={t("activate.title")}>
        <p className="text-center text-sm" style={{ color: "var(--text-soft)" }}>{t("activate.loading")}</p>
      </AuthShell>
    );
  }

  const { organization, demo, role } = preview.data;

  return (
    <AuthShell title={t("activate.title")}>
      <div className="space-y-5">
        <div className="rounded-2xl px-4 py-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
          <p className="text-lg font-semibold" style={{ color: "var(--text)" }}>{organization.name}</p>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>
            {t(`kind.${organization.provider_kind === "coach" ? "coach" : "gym"}`)} · {t(`role.${role}`)}
          </p>
        </div>
        <ul className="space-y-2 text-sm leading-6" style={{ color: "var(--text-soft)" }}>
          <li>
            {demo.rows > 0
              ? t("activate.removes", { rows: demo.rows, people: demo.people })
              : t("activate.nothingToRemove")}
          </li>
          <li>{t("activate.keeps")}</li>
          <li>{t("activate.goesLive")}</li>
        </ul>
        {redeem.error ? <AuthNotice>{localizeError(redeem.error, i18n)}</AuthNotice> : null}
        <button
          type="button"
          className={primaryButtonClass}
          style={primaryButtonStyle}
          disabled={redeem.isPending}
          onClick={() => redeem.mutate()}
        >
          {redeem.isPending ? t("activate.working") : t("activate.confirm")}
        </button>
      </div>
    </AuthShell>
  );
}
