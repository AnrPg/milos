"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useTranslations } from "next-intl";
import { useState, type ReactNode } from "react";

import type { PublicPackage } from "@/api/my-payments";
import type { PublicBoxPage } from "@/api/social";
import { useSession } from "@/components/session-provider";
import { Dialog } from "@/components/ui/Dialog";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useOrganizationMemberships } from "@/lib/organization-slug";
import { SPARK_GO_STYLE } from "@/lib/spark";

import { useBoxSales } from "./BoxSales";
import { DeskRequestDialog, WantButton, type DeskPlace } from "./DeskPayment";
import { perLabel } from "./BuyPackageSheet";
import { providerLabel, salesPageSections } from "./checkout-flow";
import { BeforePaying, money, usePackageCheckout } from "./PackageCheckout";

/**
 * The box's public sales page (mockup s5 option C), `/b/[slug]/packages`:
 * the trial first, then three packages with their prices, the rest one
 * «Όλα» away. Buying leads through sign-in or sign-up into the same
 * «Πριν πληρώσεις» as the app, with the same legal rules (ADR-248). In the
 * store apps digital-only packages are not offered (ADR-256). ADR-291: a box
 * without online payments shows its packages with «Το θέλω» instead, paid at
 * the front desk; nothing offers a payment the box cannot take.
 */
export function SalesPage({ page, line }: { page: PublicBoxPage; line: string }) {
  const t = useTranslations("Pay");
  const tDesk = useTranslations("DeskPay");
  const locale = useUiLocale();
  const router = useRouter();
  const searchParams = useSearchParams();
  const slug = page.box.slug;
  const sales = useBoxSales(slug);
  const desk = sales.desk;
  const shown = desk ? sales.deskPackages : sales.packages;
  const { trial, top, more } = salesPageSections(shown);
  const [all, setAll] = useState(false);
  const requested = searchParams.get("buy");
  const buying = shown.find((pkg) => pkg.id === requested) ?? null;
  const places: DeskPlace[] = (page.locations ?? []).map((location) => ({
    name: location.name,
    address: [location.address, location.city].filter(Boolean).join(", ") || null,
  }));

  function open(pkg: PublicPackage | null) {
    const params = new URLSearchParams(searchParams.toString());
    if (pkg) params.set("buy", pkg.id);
    else params.delete("buy");
    const query = params.toString();
    router.replace(`/b/${encodeURIComponent(slug)}/packages${query ? `?${query}` : ""}`, { scroll: false });
  }

  const provider = providerLabel(sales.provider);

  return (
    <main className="mx-auto flex w-full max-w-3xl flex-col gap-4 px-4 pb-10 pt-6" data-testid="sales-page">
      <header className="flex min-w-0 items-center gap-3">
        {page.box.logo_url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={page.box.logo_url} alt="" className="h-11 w-11 shrink-0 rounded-2xl object-cover" />
        ) : (
          <span
            aria-hidden="true"
            className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl text-sm font-extrabold"
            style={{ background: "var(--deep)", color: "var(--deep-contrast)" }}
          >
            {initials(page.box.name)}
          </span>
        )}
        <div className="min-w-0">
          <h1 className="truncate text-lg font-extrabold" style={{ color: "var(--text)" }}>
            <Link href={`/b/${encodeURIComponent(slug)}`}>{page.box.name}</Link>
          </h1>
          {line ? <p className="truncate text-xs" style={{ color: "var(--dim)" }}>{line}</p> : null}
        </div>
      </header>

      {sales.isLoading ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p> : null}

      {trial ? (
        <section className="flex flex-col gap-2 rounded-3xl p-5" style={{ background: "var(--deep)", color: "var(--deep-contrast)" }} data-testid="sales-trial">
          <p className="text-xs font-bold uppercase tracking-[0.14em]" style={{ opacity: 0.7 }}>{t("firstTime")}</p>
          <h2 className="text-xl font-extrabold">{t("trialFor", { price: money(locale, trial.base_price_cents, trial.currency) })}</h2>
          <p className="text-sm" style={{ opacity: 0.85 }}>{trial.description || t("trialPitch")}</p>
          <button
            type="button"
            onClick={() => open(trial)}
            className="mt-1 flex min-h-11 w-fit items-center justify-center rounded-2xl px-4 text-sm font-bold"
            style={SPARK_GO_STYLE}
            data-testid="sales-trial-buy"
          >
            {desk ? tDesk("want") : t("bookTrial")}
          </button>
        </section>
      ) : null}

      {top.length > 0 ? (
        <div className="grid gap-3 sm:grid-cols-3">
          {top.map((pkg, index) => (
            <article
              key={pkg.id}
              className="flex min-w-0 flex-col gap-2 rounded-3xl p-4"
              style={{
                background: index === 0 ? "color-mix(in srgb, var(--primary) 8%, var(--panel))" : "var(--panel)",
                border: `1px solid ${index === 0 ? "var(--primary)" : "var(--border)"}`,
              }}
              data-testid={`sales-package-${pkg.id}`}
            >
              <h2 className="break-words text-base font-bold" style={{ color: "var(--text)" }}>{pkg.name}</h2>
              <p>
                <span className="text-2xl font-extrabold tabular-nums" style={{ color: "var(--text)" }}>
                  {money(locale, pkg.base_price_cents, pkg.currency)}
                </span>
                <span className="text-xs" style={{ color: "var(--dim)" }}>{perLabel(t, pkg.billing_period)}</span>
              </p>
              {pkg.description ? <p className="text-xs" style={{ color: "var(--text-soft)" }}>{pkg.description}</p> : null}
              {desk ? (
                <WantButton primary={index === 0} onClick={() => open(pkg)} testId={`sales-want-${pkg.id}`} />
              ) : (
                <BuyButton primary={index === 0} onClick={() => open(pkg)} />
              )}
            </article>
          ))}
        </div>
      ) : null}

      {more.length > 0 ? (
        <section className="rounded-3xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <button
            type="button"
            aria-expanded={all}
            onClick={() => setAll(!all)}
            className="flex min-h-11 w-full items-center justify-between gap-3 text-start text-sm font-bold"
            style={{ color: "var(--text)" }}
            data-testid="sales-all"
          >
            <span>{t("allPackages", { count: top.length + more.length })}</span>
            <span aria-hidden="true" style={{ color: "var(--dim)" }}>{all ? "▴" : "▾"}</span>
          </button>
          {all ? (
            <ul className="mt-2 flex flex-col divide-y" style={{ borderColor: "var(--border)" }}>
              {more.map((pkg) => (
                <li key={pkg.id} className="flex min-w-0 items-center justify-between gap-3 py-3" style={{ borderColor: "var(--border)" }}>
                  <div className="min-w-0">
                    <p className="break-words text-sm font-semibold" style={{ color: "var(--text)" }}>{pkg.name}</p>
                    {pkg.description ? <p className="text-xs" style={{ color: "var(--dim)" }}>{pkg.description}</p> : null}
                  </div>
                  <div className="flex shrink-0 items-center gap-2">
                    <span className="text-sm font-bold tabular-nums" style={{ color: "var(--text)" }}>
                      {money(locale, pkg.base_price_cents, pkg.currency)}
                      {perLabel(t, pkg.billing_period)}
                    </span>
                    {desk ? (
                      <WantButton small onClick={() => open(pkg)} testId={`sales-want-${pkg.id}`} />
                    ) : (
                      <BuyButton small onClick={() => open(pkg)} />
                    )}
                  </div>
                </li>
              ))}
            </ul>
          ) : null}
        </section>
      ) : null}

      {desk && shown.length > 0 ? (
        <p className="text-center text-xs" style={{ color: "var(--dim)" }} data-testid="sales-desk-note">{tDesk("pageNote")}</p>
      ) : null}

      {!sales.isLoading && shown.length === 0 ? (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{desk ? tDesk("nothing") : t("nothingOnline")}</p>
      ) : null}

      {provider ? (
        <p className="text-center text-xs" style={{ color: "var(--dim)" }}>{t("paymentsVia", { provider })}</p>
      ) : null}

      {buying && desk ? (
        <DeskRequestDialog
          slug={slug}
          boxName={page.box.name}
          pkg={buying}
          places={places}
          next={`/b/${encodeURIComponent(slug)}/packages?buy=${encodeURIComponent(buying.id)}`}
          onClose={() => open(null)}
        />
      ) : buying ? (
        <BuyDialog slug={slug} boxName={page.box.name} pkg={buying} onClose={() => open(null)} />
      ) : null}
    </main>
  );
}

function BuyButton({ onClick, primary, small }: { onClick: () => void; primary?: boolean; small?: boolean }) {
  const t = useTranslations("Pay");
  return (
    <button
      type="button"
      onClick={onClick}
      className={`flex items-center justify-center rounded-2xl px-4 text-sm font-bold ${small ? "min-h-11" : "mt-auto min-h-11 w-full"}`}
      style={
        primary
          ? { background: "var(--primary)", color: "var(--primary-contrast)" }
          : { background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }
      }
    >
      {t("buy")}
    </button>
  );
}

/** «Αγορά»: sign in or sign up first, then the app's «Πριν πληρώσεις». */
function BuyDialog({ slug, boxName, pkg, onClose }: { slug: string; boxName: string; pkg: PublicPackage; onClose: () => void }) {
  const t = useTranslations("Pay");
  const locale = useUiLocale();
  const { status } = useSession();
  const memberships = useOrganizationMemberships();
  // Back here after signing in, with the same package open.
  const here = `/b/${encodeURIComponent(slug)}/packages?buy=${encodeURIComponent(pkg.id)}`;
  const member = (memberships.data ?? []).some((membership) => membership.organization.slug === slug);

  return (
    <Dialog onClose={onClose} title={t("buy")} size="sm" variant="sheet" testId="sales-buy">
      <div className="flex min-w-0 flex-col gap-3">
        <div className="flex min-w-0 items-baseline justify-between gap-3 border-b pb-3" style={{ borderColor: "var(--border)" }}>
          <p className="min-w-0 break-words text-sm font-bold" style={{ color: "var(--text)" }}>{pkg.name}</p>
          <p className="shrink-0 text-sm font-bold tabular-nums" style={{ color: "var(--text)" }}>
            {money(locale, pkg.base_price_cents, pkg.currency)}
            {perLabel(t, pkg.billing_period)}
          </p>
        </div>
        {status === "guest" ? (
          <>
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("signInToBuy")}</p>
            <div className="flex gap-2">
              <AuthLink href={`/register?next=${encodeURIComponent(here)}`} primary testId="sales-register">{t("signUp")}</AuthLink>
              <AuthLink href={`/login?next=${encodeURIComponent(here)}`} testId="sales-login">{t("signIn")}</AuthLink>
            </div>
          </>
        ) : status !== "authenticated" || memberships.isPending ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
        ) : !member ? (
          <>
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("joinFirst", { box: boxName })}</p>
            <AuthLink href={`/join/${encodeURIComponent(slug)}`} primary testId="sales-join">{t("join")}</AuthLink>
          </>
        ) : (
          <MemberCheckout slug={slug} pkg={pkg} />
        )}
      </div>
    </Dialog>
  );
}

function MemberCheckout({ slug, pkg }: { slug: string; pkg: PublicPackage }) {
  const checkout = usePackageCheckout({ slug, pkg, origin: "public" });
  return <BeforePaying checkout={checkout} pkg={pkg} />;
}

function AuthLink({ href, children, primary, testId }: { href: string; children: ReactNode; primary?: boolean; testId?: string }) {
  return (
    <Link
      href={href}
      data-testid={testId}
      className="flex min-h-11 flex-1 items-center justify-center rounded-2xl px-4 text-sm font-bold"
      style={
        primary
          ? { background: "var(--primary)", color: "var(--primary-contrast)" }
          : { background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }
      }
    >
      {children}
    </Link>
  );
}

function initials(name: string) {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word.charAt(0).toUpperCase())
    .join("");
}
