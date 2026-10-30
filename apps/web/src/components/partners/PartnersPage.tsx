"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, type ReactNode } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { PARTNERS_KEY, putPartnerProfile, putPartnerSettings, type PartnersOverview } from "@/api/partners";
import { ErrorLine } from "@/components/community/Sheet";
import { BackArrow } from "@/components/ui/BackLink";
import { Layer } from "@/components/ui/Layer";
import { MoreMenu } from "@/components/ui/MoreMenu";
import { useUiTranslations } from "@/i18n/ui";

import { PartnerBadgePill } from "./PartnerBits";
import { PartnerDeck } from "./PartnerDeck";
import { PartnerProfileSheet } from "./PartnerProfileSheet";
import { partnerErrorMessage } from "./errors";
import { PARTNERS_VERIFY_HREF, partnersStage } from "./partners-model";
import { usePartnersOverview, usePartnersToken } from "./use-partners";

/**
 * /partners (ADR-280): the public deck, full screen with the bottom bar out of
 * the way. What shows follows my verification: a short card to get verified
 * (or how it's going), a plain word after a suspension, the profile to start,
 * and then the cards.
 */
export function PartnersPage() {
  const t = useTranslations("Partners");
  const tUi = useUiTranslations();
  const router = useRouter();
  const overview = usePartnersOverview();
  const [editing, setEditing] = useState(false);
  const data = overview.data;
  const stage = data ? partnersStage(data) : null;

  return (
    <Layer>
      <div
        className="fixed inset-0 z-(--z-drawer) flex flex-col overflow-hidden"
        style={{ background: "var(--bg)" }}
        data-testid="partners-page"
      >
        <header className="mx-auto flex w-full max-w-xl items-center gap-2 px-4 pb-2 pt-[max(0.75rem,env(safe-area-inset-top))]">
          <Link
            href="/around"
            aria-label={t("back")}
            className="grid h-11 w-11 shrink-0 place-items-center rounded-full text-xl"
            style={{ background: "var(--panel-raised)", color: "var(--text)" }}
          >
            <BackArrow />
          </Link>
          <h1 className="min-w-0 flex-1 truncate text-lg font-extrabold" style={{ color: "var(--text)" }}>
            {t("title")}
          </h1>
          {stage === "deck" || stage === "paused" ? (
            <MoreMenu
              label={t("moreActions")}
              variant="pill"
              items={[
                { label: t("editProfile"), onSelect: () => setEditing(true), testId: "partners-edit-profile" },
                { label: t("visibilitySettings"), onSelect: () => router.push("/me/sharing#partners") },
              ]}
            />
          ) : null}
        </header>

        <main className="mx-auto flex min-h-0 w-full max-w-xl flex-1 flex-col px-4 pb-[max(1rem,env(safe-area-inset-bottom))]">
          {overview.isPending ? (
            <p className="text-sm" role="status" style={{ color: "var(--dim)" }}>{t("loading")}</p>
          ) : overview.isError || !data || !stage ? (
            <ErrorLine message={partnerErrorMessage(overview.error, t, tUi)} />
          ) : stage === "deck" ? (
            <PartnerDeck overview={data} />
          ) : (
            <StageCard stage={stage} overview={data} onStart={() => setEditing(true)} />
          )}
        </main>
        {editing && data ? <PartnerProfileSheet overview={data} onClose={() => setEditing(false)} /> : null}
      </div>
    </Layer>
  );
}

function StageCard({
  stage,
  overview,
  onStart,
}: {
  stage: Exclude<ReturnType<typeof partnersStage>, "deck">;
  overview: PartnersOverview;
  onStart: () => void;
}) {
  const t = useTranslations("Partners");
  switch (stage) {
    case "verify":
      return (
        <Card testId="partners-verify" title={t("verifyTitle")} body={t("verifyBody")}>
          <PrimaryLink href={PARTNERS_VERIFY_HREF}>{t("verifyStart")}</PrimaryLink>
        </Card>
      );
    case "in_review":
      return (
        <Card testId="partners-in-review" title={t("reviewTitle")} body={t("reviewBody")}>
          <SecondaryLink href={PARTNERS_VERIFY_HREF}>{t("reviewOpen")}</SecondaryLink>
        </Card>
      );
    case "rejected":
      return (
        <Card testId="partners-rejected" title={t("rejectedTitle")} body={t("rejectedBody")}>
          <PrimaryLink href={PARTNERS_VERIFY_HREF}>{t("rejectedOpen")}</PrimaryLink>
        </Card>
      );
    case "suspended":
      return <Card testId="partners-suspended" title={t("suspendedTitle")} body={t("suspendedBody")} />;
    case "setup":
      return (
        <Card
          testId="partners-setup"
          badge={overview.eligibility.method === "sponsors" ? t("verifiedSponsors") : t("verifiedMember")}
          title={t("introTitle")}
          body={t("introBody")}
        >
          <PrimaryButton onClick={onStart}>{t("introStart")}</PrimaryButton>
        </Card>
      );
    case "paused":
      return <Paused overview={overview} onEdit={onStart} />;
  }
}

/** Off in Ρυθμίσεις, or paused from the profile: one button brings me back. */
function Paused({ overview, onEdit }: { overview: PartnersOverview; onEdit: () => void }) {
  const t = useTranslations("Partners");
  const tUi = useUiTranslations();
  const token = usePartnersToken();
  const queryClient = useQueryClient();
  const profile = overview.profile;
  const resume = useMutation({
    mutationFn: async () => {
      if (profile?.paused) await putPartnerSettings(token!, true);
      if (profile && !profile.active) await putPartnerProfile(token!, { active: true });
    },
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: PARTNERS_KEY }),
  });
  return (
    <Card testId="partners-paused" title={t("pausedTitle")} body={t("pausedBody")}>
      <PrimaryButton onClick={() => resume.mutate()} disabled={resume.isPending}>{t("resume")}</PrimaryButton>
      <button type="button" onClick={onEdit} className="min-h-11 text-sm font-semibold" style={{ color: "var(--primary)" }}>
        {t("editProfile")}
      </button>
      <ErrorLine message={partnerErrorMessage(resume.error, t, tUi)} />
    </Card>
  );
}

function Card({ title, body, badge, testId, children }: { title: string; body: string; badge?: string; testId: string; children?: ReactNode }) {
  return (
    <section
      className="mt-4 flex flex-col gap-3 rounded-3xl p-5"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      data-testid={testId}
    >
      {badge ? <PartnerBadgePill>{badge}</PartnerBadgePill> : null}
      <h2 className="text-xl font-extrabold" style={{ color: "var(--text)" }}>{title}</h2>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{body}</p>
      {children ? <div className="flex flex-col gap-2 pt-1">{children}</div> : null}
    </section>
  );
}

const buttonClass = "flex min-h-12 items-center justify-center rounded-2xl px-4 text-sm font-bold disabled:opacity-50";

function PrimaryButton({ onClick, disabled, children }: { onClick: () => void; disabled?: boolean; children: string }) {
  return (
    <button type="button" onClick={onClick} disabled={disabled} className={buttonClass} style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
      {children}
    </button>
  );
}

function PrimaryLink({ href, children }: { href: string; children: string }) {
  return (
    <Link href={href} className={buttonClass} style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
      {children}
    </Link>
  );
}

function SecondaryLink({ href, children }: { href: string; children: string }) {
  return (
    <Link href={href} className={buttonClass} style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}>
      {children}
    </Link>
  );
}
