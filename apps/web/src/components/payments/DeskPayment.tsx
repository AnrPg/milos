"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useEffect, useRef, useState, type ReactNode } from "react";

import type { PublicPackage } from "@/api/my-payments";
import {
  cancelPackageRequest,
  fetchMyPackageRequests,
  myPackageRequestsKey,
  requestPackage,
  type PackageRequest,
} from "@/api/package-requests";
import { useSession } from "@/components/session-provider";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useOrganizationMemberships } from "@/lib/organization-slug";
import { FRESHNESS } from "@/lib/query-policy";

import { PackageChoice, perLabel } from "./BuyPackageSheet";
import { renewalPackages } from "./checkout-flow";
import { holdDateLabel } from "./desk-payment";
import { money } from "./PackageCheckout";
import { usePayError } from "./PayParts";

/*
 * ADR-291 (mockup «Πληρωμή στην υποδοχή», option 1C): a box that takes no
 * online payments shows its packages with «Το θέλω». Asking puts the package
 * in the person's Συνδρομή as «Περιμένει πληρωμή» for 14 days and in the
 * desk's «Εκκρεμότητες»; they pay at the desk and it starts at once. Nothing
 * here offers a payment the box cannot take.
 */

/** Where the box's front desk is: shown under the steps when the page knows it. */
export type DeskPlace = { name: string; address: string | null };

const BUTTON = "flex min-h-11 items-center justify-center rounded-2xl px-4 text-sm font-bold";
const PRIMARY = { background: "var(--primary)", color: "var(--primary-contrast)" } as const;
const SECONDARY = { background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" } as const;

/** «Το θέλω» on a package card. */
export function WantButton({ onClick, primary, small, testId }: { onClick: () => void; primary?: boolean; small?: boolean; testId?: string }) {
  const t = useTranslations("DeskPay");
  return (
    <button
      type="button"
      onClick={onClick}
      className={`${BUTTON} ${small ? "" : "mt-auto w-full"}`}
      style={primary ? PRIMARY : SECONDARY}
      data-testid={testId}
    >
      {t("want")}
    </button>
  );
}

/** The three steps at the desk, and where it is. */
export function DeskSteps({ amount, places, known }: { amount: string | null; places?: DeskPlace[]; known?: boolean }) {
  const t = useTranslations("DeskPay");
  return (
    <>
      <ol className="flex list-decimal flex-col gap-2 ps-5 text-sm" style={{ color: "var(--text)" }}>
        <li>{known ? t("stepName") : t("stepTell")}</li>
        <li>{amount ? t("stepPayAmount", { amount }) : t("stepPay")}</li>
        <li>{t("stepStarts")}</li>
      </ol>
      {places && places.length > 0 ? (
        <ul className="flex flex-col gap-2" data-testid="desk-places">
          {places.slice(0, 2).map((place) => (
            <li key={place.name} className="flex flex-col rounded-2xl px-3 py-2 text-sm" style={{ background: "var(--panel-muted)" }}>
              <span className="font-bold" style={{ color: "var(--text)" }}>{t("deskAt", { place: place.name })}</span>
              {place.address ? <span style={{ color: "var(--text-soft)" }}>{place.address}</span> : null}
            </li>
          ))}
        </ul>
      ) : null}
    </>
  );
}

function PackageLine({ name, amount }: { name: string; amount: string }) {
  return (
    <div className="flex min-w-0 items-baseline justify-between gap-3 border-b pb-3" style={{ borderColor: "var(--border)" }}>
      <p className="min-w-0 break-words text-sm font-bold" style={{ color: "var(--text)" }}>{name}</p>
      <p className="shrink-0 text-sm font-bold tabular-nums" style={{ color: "var(--text)" }}>{amount}</p>
    </div>
  );
}

function Actions({ children }: { children: ReactNode }) {
  return <div className="flex flex-wrap gap-2">{children}</div>;
}

/**
 * The centred window «Το θέλω» opens. A member of the box gets the package
 * held at once; anyone else learns how to pay at the desk, and how to join.
 */
export function DeskRequestDialog({
  slug,
  boxName,
  pkg,
  places,
  next,
  onClose,
}: {
  slug: string;
  boxName: string;
  pkg: PublicPackage;
  places?: DeskPlace[];
  /** Where sign-in brings the person back to. */
  next: string;
  onClose: () => void;
}) {
  const t = useTranslations("DeskPay");
  const tPay = useTranslations("Pay");
  const locale = useUiLocale();
  const { status } = useSession();
  const memberships = useOrganizationMemberships();
  const member = (memberships.data ?? []).some((membership) => membership.organization.slug === slug);
  const amount = `${money(locale, pkg.base_price_cents, pkg.currency)}${perLabel(tPay, pkg.billing_period)}`;

  if (status === "authenticated" && member) {
    return <HeldDialog slug={slug} pkg={pkg} places={places} onClose={onClose} />;
  }

  return (
    <Dialog onClose={onClose} title={t("title")} size="sm" variant="center" testId="desk-pay">
      <div className="flex min-w-0 flex-col gap-3">
        <PackageLine name={pkg.name} amount={amount} />
        <DeskSteps amount={money(locale, pkg.base_price_cents, pkg.currency)} places={places} />
        {status === "guest" ? (
          <>
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("signInToHold")}</p>
            <Actions>
              <AuthLink href={`/register?next=${encodeURIComponent(next)}`} primary testId="desk-register">{t("signUp")}</AuthLink>
              <AuthLink href={`/login?next=${encodeURIComponent(next)}`} testId="desk-login">{t("signIn")}</AuthLink>
            </Actions>
          </>
        ) : status !== "authenticated" || memberships.isPending ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
        ) : (
          <>
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("joinToHold", { box: boxName })}</p>
            <Actions>
              <AuthLink href={`/join/${encodeURIComponent(slug)}`} primary testId="desk-join">{t("join")}</AuthLink>
            </Actions>
          </>
        )}
      </div>
    </Dialog>
  );
}

/** Asks for the package when opened (asking twice returns the same request) and says until when it is held. */
function HeldDialog({ slug, pkg, places, onClose }: { slug: string; pkg: PublicPackage; places?: DeskPlace[]; onClose: () => void }) {
  const t = useTranslations("DeskPay");
  const request = useRequestPackage(slug);
  const asked = useRef(false);
  const { mutate } = request;

  useEffect(() => {
    if (asked.current) return;
    asked.current = true;
    mutate(pkg.id);
  }, [mutate, pkg.id]);

  return (
    <Dialog onClose={onClose} title={t("heldTitle")} size="sm" variant="center" testId="desk-held">
      <HeldBody slug={slug} request={request} retry={() => mutate(pkg.id)} places={places} onClose={onClose} />
    </Dialog>
  );
}

function HeldBody({
  slug,
  request,
  retry,
  places,
  onClose,
}: {
  slug: string;
  request: ReturnType<typeof useRequestPackage>;
  retry: () => void;
  places?: DeskPlace[];
  onClose: () => void;
}) {
  const t = useTranslations("DeskPay");
  const locale = useUiLocale();
  const payError = usePayError();
  const cancel = useCancelRequest(slug);
  const held = request.data?.request;

  if (request.isError) {
    return (
      <div className="flex flex-col gap-3">
        <ErrorNotice>{payError(request.error)}</ErrorNotice>
        <Actions>
          <button type="button" onClick={retry} className={`${BUTTON} flex-1`} style={PRIMARY}>{t("tryAgain")}</button>
        </Actions>
      </div>
    );
  }
  if (!held) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("holding")}</p>;

  const amount = money(locale, held.price_cents, held.currency);
  return (
    <div className="flex min-w-0 flex-col gap-3">
      <PackageLine name={held.package_name} amount={amount} />
      <p className="text-sm" style={{ color: "var(--text)" }}>{t("heldBody")}</p>
      <p className="text-sm" style={{ color: "var(--text-soft)" }} data-testid="desk-held-until">
        {t("heldUntil", { days: held.hold_days, date: holdDateLabel(locale, held.hold_until) })}
      </p>
      <DeskSteps amount={amount} places={places} known />
      {cancel.isError ? <ErrorNotice>{payError(cancel.error)}</ErrorNotice> : null}
      <Actions>
        <button
          type="button"
          onClick={() => cancel.mutate(held.id, { onSuccess: onClose })}
          disabled={cancel.isPending}
          className={`${BUTTON} flex-1`}
          style={SECONDARY}
          data-testid="desk-held-cancel"
        >
          {t("cancelRequest")}
        </button>
        <button type="button" onClick={onClose} className={`${BUTTON} flex-1`} style={PRIMARY} data-testid="desk-held-ok">
          {t("gotIt")}
        </button>
      </Actions>
    </div>
  );
}

/** Box › Συνδρομή › «Ανανέωση» at a box without online payments: pick, then «Το θέλω». */
export function DeskRenewDialog({ slug, packages, onClose }: { slug: string; packages: PublicPackage[]; onClose: () => void }) {
  const t = useTranslations("DeskPay");
  const tPay = useTranslations("Pay");
  const renewals = renewalPackages(packages);
  const [chosen, setChosen] = useState<PublicPackage | null>(renewals[0] ?? null);
  const [held, setHeld] = useState<PublicPackage | null>(null);

  if (held) return <HeldDialog slug={slug} pkg={held} onClose={onClose} />;

  return (
    <Dialog onClose={onClose} title={tPay("renewTitle")} size="sm" variant="center" testId="desk-renew">
      <div className="flex min-w-0 flex-col gap-2">
        <div role="radiogroup" aria-label={tPay("renewTitle")} className="flex flex-col gap-2">
          {renewals.map((pkg) => (
            <PackageChoice key={pkg.id} pkg={pkg} checked={chosen?.id === pkg.id} onSelect={() => setChosen(pkg)} />
          ))}
        </div>
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("renewHint")}</p>
        <button
          type="button"
          disabled={!chosen}
          onClick={() => chosen && setHeld(chosen)}
          className={BUTTON}
          style={PRIMARY}
          data-testid="desk-renew-want"
        >
          {t("want")}
        </button>
      </div>
    </Dialog>
  );
}

/**
 * Box › Συνδρομή: the packages waiting for payment at the desk, each with
 * its last day, «Πώς πληρώνω» and «Δεν το θέλω». Nothing shows when none waits.
 */
export function PendingPackages({ slug }: { slug: string }) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const requests = useQuery({
    queryKey: myPackageRequestsKey(slug),
    enabled: Boolean(token),
    queryFn: () => fetchMyPackageRequests(token!, slug),
    staleTime: FRESHNESS.reference,
    retry: false,
  });
  const rows = requests.data?.requests ?? [];
  if (rows.length === 0) return null;
  return (
    <div className="flex flex-col gap-2" data-testid="pending-packages">
      {rows.map((request) => (
        <PendingPackage key={request.id} slug={slug} request={request} />
      ))}
    </div>
  );
}

function PendingPackage({ slug, request }: { slug: string; request: PackageRequest }) {
  const t = useTranslations("DeskPay");
  const locale = useUiLocale();
  const payError = usePayError();
  const cancel = useCancelRequest(slug);
  const [how, setHow] = useState(false);
  const amount = money(locale, request.price_cents, request.currency);

  return (
    <article className="flex min-w-0 flex-col gap-2 rounded-2xl p-4" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }} data-testid={`pending-package-${request.id}`}>
      <div className="flex min-w-0 items-center justify-between gap-2">
        <span
          className="rounded-full px-2.5 py-0.5 text-xs font-bold"
          style={{ background: "color-mix(in srgb, var(--warning) 16%, var(--panel))", color: "var(--text)" }}
        >
          {t("pending")}
        </span>
        <span className="text-sm font-bold tabular-nums" style={{ color: "var(--text)" }}>{amount}</span>
      </div>
      <p className="break-words text-base font-bold" style={{ color: "var(--text)" }}>{request.package_name}</p>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>
        {t("pendingBody", { date: holdDateLabel(locale, request.hold_until) })}
      </p>
      {cancel.isError ? <ErrorNotice>{payError(cancel.error)}</ErrorNotice> : null}
      <Actions>
        <button type="button" onClick={() => setHow(true)} className={`${BUTTON} flex-1`} style={SECONDARY} data-testid="pending-how">
          {t("howToPay")}
        </button>
        <button
          type="button"
          onClick={() => cancel.mutate(request.id)}
          disabled={cancel.isPending}
          className={BUTTON}
          style={{ color: "var(--text-soft)" }}
          data-testid="pending-cancel"
        >
          {t("dontWant")}
        </button>
      </Actions>
      {how ? (
        <Dialog onClose={() => setHow(false)} title={t("title")} size="sm" variant="center" testId="pending-how-dialog">
          <div className="flex min-w-0 flex-col gap-3">
            <PackageLine name={request.package_name} amount={amount} />
            <DeskSteps amount={amount} known />
            <button type="button" onClick={() => setHow(false)} className={BUTTON} style={PRIMARY}>{t("gotIt")}</button>
          </div>
        </Dialog>
      ) : null}
    </article>
  );
}

function useRequestPackage(slug: string) {
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (packageId: string) => requestPackage(tokens!.access_token, slug, packageId),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: myPackageRequestsKey(slug) }),
  });
}

function useCancelRequest(slug: string) {
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (requestId: string) => cancelPackageRequest(tokens!.access_token, slug, requestId),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: myPackageRequestsKey(slug) }),
  });
}

function AuthLink({ href, children, primary, testId }: { href: string; children: ReactNode; primary?: boolean; testId?: string }) {
  return (
    <Link href={href} data-testid={testId} className={`${BUTTON} flex-1`} style={primary ? PRIMARY : SECONDARY}>
      {children}
    </Link>
  );
}
