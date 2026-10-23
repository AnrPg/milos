/**
 * ADR-187: the reset link and the message a handler mails from their own
 * mailbox. Pure, so the encoding can be tested without a browser.
 */

/** The link the person opens. The token rides in the fragment, so it never reaches a server log. */
export function resetLinkFor(origin: string, token: string) {
  return `${origin.replace(/\/+$/, "")}/reset-password#token=${encodeURIComponent(token)}`;
}

/** Mail clients expect CRLF line breaks in a mailto body (RFC 6068). */
function crlf(text: string) {
  return text.replace(/\r\n|\r|\n/g, "\r\n");
}

/**
 * A `mailto:` URL with the recipient, subject and body filled in. Every part
 * is percent-encoded (spaces as %20, never "+", which some clients show
 * literally); the "@" of the address stays readable.
 */
export function buildMailto({ to, subject, body }: { to: string; subject: string; body: string }) {
  const address = encodeURIComponent(to.trim()).replace(/%40/g, "@");
  const query = [`subject=${encodeURIComponent(subject)}`, `body=${encodeURIComponent(crlf(body))}`].join("&");
  return `mailto:${address}?${query}`;
}

const UNITS: Array<[Intl.RelativeTimeFormatUnit, number]> = [
  ["day", 86_400_000],
  ["hour", 3_600_000],
  ["minute", 60_000],
];

/** "5 minutes ago", "in 23 hours": the nearest whole unit, in the viewer's language. */
export function relativeTime(iso: string, now: number, locale: string) {
  const time = new Date(iso).getTime();
  if (Number.isNaN(time)) return "";
  const diff = time - now;
  const format = new Intl.RelativeTimeFormat(locale, { numeric: "auto" });
  for (const [unit, size] of UNITS) {
    if (Math.abs(diff) >= size) return format.format(Math.round(diff / size), unit);
  }
  return format.format(0, "minute");
}
