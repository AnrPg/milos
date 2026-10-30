"use client";

import { useTranslations } from "next-intl";
import { useId, useState } from "react";

import type { PublicPackage } from "@/api/my-payments";
import { Dialog } from "@/components/ui/Dialog";
import { useUiLocale } from "@/i18n/use-ui-locale";

import { bookingOffer, renewalPackages, type CheckoutOrigin } from "./checkout-flow";
import { BeforePaying, money, usePackageCheckout, usePayLabel, type BookingTarget } from "./PackageCheckout";
import { ChoiceRow, PayButton, usePayError } from "./PayParts";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/** How many packages the «Ανανέωση» sheet lists before «Όλα». */
const FIRST = 3;

export type BuyMode = { kind: "renew" } | { kind: "booking"; booking: BookingTarget };

/**
 * Mockup s4 option B: two small sheets where the member already is (Box or
 * the schedule). Sheet 1 is what they buy: «Ανανέωση» lists the box's
 * packages; booking a class without a package offers «Μόνο αυτή η επίσκεψη»
 * (paid and booked in one press) or a package that books the class once it
 * is paid. Sheet 2 «Πριν πληρώσεις» asks the two legal questions.
 */
export function BuyPackageSheet({
  slug,
  packages,
  mode,
  origin,
  onClose,
}: {
  slug: string;
  packages: PublicPackage[];
  mode: BuyMode;
  origin: CheckoutOrigin;
  onClose: () => void;
}) {
  const t = useTranslations("Pay");
  const offer = bookingOffer(packages);
  const renewals = renewalPackages(packages);
  const [step, setStep] = useState<"pick" | "before">("pick");
  const [chosen, setChosen] = useState<PublicPackage | null>(() =>
    mode.kind === "renew" ? (renewals[0] ?? null) : (offer.visit ?? offer.pack),
  );
  const booking = mode.kind === "booking" ? mode.booking : null;

  const title =
    step === "before" ? t("beforePaying") : mode.kind === "renew" ? t("renewTitle") : (booking?.label ?? t("renewTitle"));

  return (
    <Dialog onClose={onClose} title={title} size="sm" variant="sheet" testId="pay-sheet">
      {step === "before" && chosen ? (
        <BeforeStep
          key={chosen.id}
          slug={slug}
          pkg={chosen}
          booking={booking}
          origin={origin}
          onBack={() => setStep("pick")}
        />
      ) : mode.kind === "renew" ? (
        <RenewStep packages={renewals} chosen={chosen} onChoose={setChosen} onContinue={() => setStep("before")} />
      ) : (
        <BookingStep
          slug={slug}
          booking={mode.booking}
          visit={offer.visit}
          pack={offer.pack}
          chosen={chosen}
          onChoose={setChosen}
          origin={origin}
          onContinue={() => setStep("before")}
        />
      )}
    </Dialog>
  );
}

function PackageChoice({ pkg, checked, onSelect }: { pkg: PublicPackage; checked: boolean; onSelect: () => void }) {
  const t = useTranslations("Pay");
  const locale = useUiLocale();
  return (
    <ChoiceRow
      checked={checked}
      onSelect={onSelect}
      title={pkg.name}
      detail={pkg.description ?? undefined}
      end={`${money(locale, pkg.base_price_cents, pkg.currency)}${perLabel(t, pkg.billing_period)}`}
      testId={`pay-package-${pkg.id}`}
    />
  );
}

function RenewStep({
  packages,
  chosen,
  onChoose,
  onContinue,
}: {
  packages: PublicPackage[];
  chosen: PublicPackage | null;
  onChoose: (pkg: PublicPackage) => void;
  onContinue: () => void;
}) {
  const t = useTranslations("Pay");
  const [all, setAll] = useState(false);
  const listId = useId();
  const shown = all ? packages : packages.slice(0, FIRST);

  return (
    <div className="flex min-w-0 flex-col gap-2">
      <div role="radiogroup" aria-label={t("renewTitle")} id={listId} className="flex flex-col gap-2">
        {shown.map((pkg) => (
          <PackageChoice key={pkg.id} pkg={pkg} checked={chosen?.id === pkg.id} onSelect={() => onChoose(pkg)} />
        ))}
      </div>
      {packages.length > FIRST ? (
        <button
          type="button"
          aria-expanded={all}
          aria-controls={listId}
          onClick={() => setAll(!all)}
          className="min-h-11 text-sm font-semibold"
          style={{ color: "var(--primary)" }}
        >
          {all ? t("fewer") : t("allPackages", { count: packages.length })}
        </button>
      ) : null}
      <PayButton disabled={!chosen} onClick={onContinue} testId="pay-continue">
        {t("continue")}
      </PayButton>
    </div>
  );
}

function BookingStep({
  slug,
  booking,
  visit,
  pack,
  chosen,
  onChoose,
  origin,
  onContinue,
}: {
  slug: string;
  booking: BookingTarget;
  visit: PublicPackage | null;
  pack: PublicPackage | null;
  chosen: PublicPackage | null;
  onChoose: (pkg: PublicPackage) => void;
  origin: CheckoutOrigin;
  onContinue: () => void;
}) {
  const t = useTranslations("Pay");
  const locale = useUiLocale();
  const visitChosen = Boolean(visit && chosen?.id === visit.id);

  return (
    <div className="flex min-w-0 flex-col gap-2">
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("noPackageForClass")}</p>
      <div role="radiogroup" aria-label={booking.label} className="flex flex-col gap-2">
        {visit ? (
          <ChoiceRow
            checked={visitChosen}
            onSelect={() => onChoose(visit)}
            title={t("onlyThisVisit")}
            detail={t("onlyThisVisitDetail")}
            end={money(locale, visit.base_price_cents, visit.currency)}
            testId="pay-visit"
          />
        ) : null}
        {pack ? (
          <ChoiceRow
            checked={chosen?.id === pack.id}
            onSelect={() => onChoose(pack)}
            title={t("packageNamed", { name: pack.name })}
            detail={t("packageBooksClass")}
            end={money(locale, pack.base_price_cents, pack.currency)}
            testId="pay-pack"
          />
        ) : null}
      </div>
      {visit && visitChosen ? (
        <VisitPay key={visit.id} slug={slug} visit={visit} booking={booking} origin={origin} />
      ) : (
        <PayButton disabled={!chosen} onClick={onContinue} testId="pay-continue">
          {t("continue")}
        </PayButton>
      )}
    </div>
  );
}

/** «Μόνο αυτή η επίσκεψη»: no questions, one button to the provider's page. */
function VisitPay({ slug, visit, booking, origin }: { slug: string; visit: PublicPackage; booking: BookingTarget; origin: CheckoutOrigin }) {
  const t = useTranslations("Pay");
  const payLabel = usePayLabel();
  const payError = usePayError();
  const checkout = usePackageCheckout({ slug, pkg: visit, booking, origin });
  const { terms, asksStart, pay, ready } = checkout;

  if (terms.isPending) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (terms.isError) return <ErrorNotice>{payError(terms.error)}</ErrorNotice>;
  // Where the box's country still gives 14 days, the start question comes first.
  if (asksStart) return <BeforePaying checkout={checkout} pkg={visit} andBook />;

  return (
    <>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("datedVisitNoWithdrawal")}</p>
      {!terms.data.available ? <ErrorNotice>{t("errorUnavailable")}</ErrorNotice> : null}
      <PayButton disabled={!ready || pay.isPending} onClick={() => pay.mutate()} testId="pay-submit">
        {payLabel(visit.base_price_cents, visit.currency, terms.data.provider, true)}
      </PayButton>
      {pay.isError ? <ErrorNotice variant="field">{payError(pay.error)}</ErrorNotice> : null}
    </>
  );
}

function BeforeStep({
  slug,
  pkg,
  booking,
  origin,
  onBack,
}: {
  slug: string;
  pkg: PublicPackage;
  booking: BookingTarget | null;
  origin: CheckoutOrigin;
  onBack: () => void;
}) {
  const t = useTranslations("Pay");
  const locale = useUiLocale();
  const checkout = usePackageCheckout({ slug, pkg, booking, origin });

  return (
    <div className="flex min-w-0 flex-col gap-3">
      <div className="flex min-w-0 items-center gap-2">
        <button
          type="button"
          onClick={onBack}
          aria-label={t("back")}
          className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full text-lg"
          style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
        >
          <span aria-hidden="true">‹</span>
        </button>
        <p className="min-w-0 flex-1 truncate text-sm font-bold" style={{ color: "var(--text)" }}>{pkg.name}</p>
        <p className="shrink-0 text-sm font-bold tabular-nums" style={{ color: "var(--text)" }}>
          {money(locale, pkg.base_price_cents, pkg.currency)}
        </p>
      </div>
      <BeforePaying checkout={checkout} pkg={pkg} />
    </div>
  );
}

export function perLabel(t: ReturnType<typeof useTranslations>, period: string) {
  switch (period) {
    case "monthly":
      return t("per.monthly");
    case "quarterly":
      return t("per.quarterly");
    case "semiannual":
      return t("per.semiannual");
    case "annual":
      return t("per.annual");
    default:
      return "";
  }
}
