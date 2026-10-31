import type { PublicPackage } from "@/api/my-payments";

/*
 * ADR-291: paying at the front desk when the box takes no online payments.
 * The API decides what is listed and how long a request is held; this module
 * only shapes that answer for the screens.
 */

/** A box-local `YYYY-MM-DD` as a local date, never shifted by the viewer's zone. */
export function localDate(value: string): Date | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return null;
  return new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
}

/** «14 Νοεμβρίου»: the last day a request is held, in the person's language. */
export function holdDateLabel(locale: string, holdUntil: string): string {
  const date = localDate(holdUntil);
  return date ? date.toLocaleDateString(locale, { day: "numeric", month: "long" }) : holdUntil;
}

/** Whether the box sells nothing online now, so its packages are asked for at the desk. */
export function deskMode(data: { online_payments: boolean } | null | undefined): boolean {
  return data != null && data.online_payments === false;
}

/** The packages a person can ask for at the desk (the API lists them; a free one needs no payment). */
export function deskPackages(data: { online_payments: boolean; packages: PublicPackage[] } | null | undefined): PublicPackage[] {
  return deskMode(data) ? data!.packages.filter((pkg) => pkg.base_price_cents > 0) : [];
}
