/**
 * One clock convention for every time the UI shows (product owner, 2026-10-29).
 *
 * Greek is always written on the 24-hour clock («06:00», «18:30»), never with
 * «π.μ./μ.μ.», although Intl's Greek data defaults to 12 hours. Every other
 * locale keeps its own convention as Intl gives it (English 12-hour, German
 * 24-hour, and so on).
 *
 * Every options object that shows hours (`hour` or `timeStyle`) goes through
 * `withClock`, directly or through `clockFormat` / `formatClock` or the
 * zoned helpers in lib/zoned-time, which call it. A guard test
 * (clock-guard.test.ts) fails when a component formats hours without it.
 */

/** Languages always shown on the 24-hour clock, whatever Intl's default. */
const TWENTY_FOUR_HOUR_LANGUAGES = new Set(["el"]);

type LocaleArg = string | readonly string[] | undefined;

function primaryLocale(locale: LocaleArg): string | undefined {
  if (typeof locale === "string") return locale;
  if (locale && locale.length > 0) return locale[0];
  if (typeof navigator !== "undefined" && navigator.language) return navigator.language;
  return undefined;
}

/** True when `locale` is always shown on the 24-hour clock (Greek). */
export function uses24HourClock(locale: LocaleArg): boolean {
  const tag = primaryLocale(locale);
  if (!tag) return false;
  return TWENTY_FOUR_HOUR_LANGUAGES.has(tag.toLowerCase().split(/[-_]/)[0]);
}

function showsHours(options: Intl.DateTimeFormatOptions): boolean {
  return options.hour !== undefined || options.timeStyle !== undefined;
}

/**
 * The options with this locale's clock applied: for Greek, any options that
 * show hours get `hourCycle: "h23"` (and lose a stray `hour12`). Options that
 * show no hours, and every other locale, come back unchanged.
 */
export function withClock<Options extends Intl.DateTimeFormatOptions>(locale: LocaleArg, options: Options): Options {
  if (!showsHours(options) || !uses24HourClock(locale)) return options;
  const clocked: Intl.DateTimeFormatOptions = { ...options, hourCycle: "h23" };
  delete clocked.hour12;
  return clocked as Options;
}

/** `new Intl.DateTimeFormat` with this locale's clock applied. */
export function clockFormat(locale: LocaleArg, options: Intl.DateTimeFormatOptions): Intl.DateTimeFormat {
  return new Intl.DateTimeFormat(locale as string | string[] | undefined, withClock(locale, options));
}

/** A moment as text on this locale's clock; «18:30» by default. */
export function formatClock(
  at: Date | string | number,
  locale: LocaleArg,
  options: Intl.DateTimeFormatOptions = { hour: "2-digit", minute: "2-digit" },
): string {
  const date = at instanceof Date ? at : new Date(at);
  if (Number.isNaN(date.getTime())) return "";
  return clockFormat(locale, options).format(date);
}
