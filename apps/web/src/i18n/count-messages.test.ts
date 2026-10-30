import fs from "node:fs";
import path from "node:path";
import { IntlMessageFormat } from "intl-messageformat";
import { describe, expect, it } from "vitest";

// A count shown in the UI is always one ICU message with the number inside it
// ("{count, plural, one {# overdue invoice} other {# overdue invoices}}"), so
// every locale controls the spacing, word order and plural form. Gluing a
// number to translated text ("1" + "overdue invoices") is what produced
// "1ληξιπρόθεσμα τιμολόγια" on the staff home.

const locales = ["en", "el", "ar", "ru", "de", "es", "pt-PT", "he", "it", "bg", "nl", "fr"];

type AstNode = { type: number; value?: string; pluralType?: string; options?: Record<string, { value: AstNode[] }>; children?: AstNode[] };
const PLURAL = 6;
const TAG = 8;

function catalog(locale: string) {
  return (JSON.parse(fs.readFileSync(path.resolve("messages", `${locale}.json`), "utf8")) as { Ui: Record<string, string> }).Ui;
}

function pluralNodes(nodes: AstNode[]): AstNode[] {
  return nodes.flatMap((node) => [
    ...(node.type === PLURAL ? [node] : []),
    ...Object.values(node.options ?? {}).flatMap((option) => pluralNodes(option.value)),
    ...(node.type === TAG ? pluralNodes(node.children ?? []) : []),
  ]);
}

// Categories whose fallback to "other" is still grammatical with a numeral:
// Arabic "0 X" and Hebrew "2 Xים" read correctly from the "other" branch.
const optionalCategories: Record<string, string[]> = { ar: ["zero"], he: ["two"] };

// Every plural category a real count (0–1000) can land in, per locale.
function reachableCategories(locale: string) {
  const rules = new Intl.PluralRules(locale);
  const categories = new Map<string, number>();
  for (let n = 1000; n >= 0; n -= 1) categories.set(rules.select(n), n);
  return categories;
}

describe("count messages", () => {
  it.each(locales)("%s: every plural covers each category its counts can reach", (locale) => {
    const reachable = reachableCategories(locale);
    const gaps: string[] = [];

    for (const [key, message] of Object.entries(catalog(locale))) {
      if (!message.includes("plural,")) continue;
      const ast = new IntlMessageFormat(message, locale).getAst() as AstNode[];
      for (const node of pluralNodes(ast)) {
        if (node.pluralType !== "cardinal") continue;
        const options = Object.keys(node.options ?? {});
        if (!options.includes("other")) gaps.push(`${key}: no "other"`);
        for (const [category, sample] of reachable) {
          if (category === "other" || options.includes(category)) continue;
          if (optionalCategories[locale]?.includes(category)) continue;
          gaps.push(`${key} (${node.value}): no "${category}" branch, e.g. ${sample}`);
        }
      }
    }

    expect(gaps).toEqual([]);
  });

  it("formats the staff home alerts with a space and the right plural", () => {
    const format = (locale: string, key: string, count: number) =>
      new IntlMessageFormat(catalog(locale)[key]!, locale).format({ count }) as string;

    expect(format("el", "adminAlertExpiringMemberships", 1)).toBe("1 συνδρομή λήγει μέσα σε 30 ημέρες");
    expect(format("el", "adminAlertExpiringMemberships", 3)).toBe("3 συνδρομές λήγουν μέσα σε 30 ημέρες");
    expect(format("el", "adminAlertOverdueInvoices", 1)).toBe("1 ληξιπρόθεσμο τιμολόγιο");
    expect(format("en", "adminAlertOverdueInvoices", 2)).toBe("2 overdue invoices");
    expect(format("ru", "adminAlertOverdueInvoices", 5)).toBe("5 просроченных счетов");
    expect(format("ru", "adminAlertOverdueInvoices", 22)).toBe("22 просроченных счёта");
    expect(format("ar", "adminAlertOverdueInvoices", 2)).toBe("فاتورتان متأخرتان");
    expect(format("he", "adminAlertOverdueInvoices", 1)).toBe("חשבונית אחת באיחור");
  });
});

// Source guard: translated text is never concatenated with a value. Pass the
// value to the message as an ICU argument instead.
const sourceRoot = path.resolve("src");

// Whole greeting sentences around a nickname; the name never changes their grammar.
const concatenationAllowed = new Set(["components/member-app/home/GreetingCard.tsx"]);

const COUNT_LIKE = /\.length\b|[cC]ount\b|_count\b|\btotal\b|\bremaining\b|\.sets\b|\bprogress\b|\bspots_remaining\b/;

function sourceFiles(dir: string): string[] {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) return sourceFiles(full);
    return /\.tsx?$/.test(entry.name) && !/\.test\.tsx?$/.test(entry.name) ? [full] : [];
  });
}

function lineOf(source: string, index: number) {
  return source.slice(0, index).split("\n").length;
}

describe("number and text are never glued together", () => {
  const files = sourceFiles(sourceRoot).map((file) => ({ file: path.relative(sourceRoot, file), source: fs.readFileSync(file, "utf8") }));

  it("never concatenates a value with a translated message", () => {
    const hits: string[] = [];
    const concat = /i18n\("[A-Za-z0-9_]+"(?:,\s*\{[^}]*\})?\)\s*\+\s*[^"'\s]|[^"'\s]\s*\+\s*i18n\(/g;
    for (const { file, source } of files) {
      if (concatenationAllowed.has(file)) continue;
      for (const match of source.matchAll(concat)) hits.push(`${file}:${lineOf(source, match.index)} ${match[0]}`);
    }
    expect(hits).toEqual([]);
  });

  it("never puts a count in front of a translated noun in JSX or a template", () => {
    const hits: string[] = [];
    const adjacent = [/\{([^{}]{1,120})\}\s*\{\s*i18n\("/g, /\$\{([^{}]{1,120})\}\s*\$\{i18n\("/g];
    for (const { file, source } of files) {
      for (const pattern of adjacent) {
        for (const match of source.matchAll(pattern)) {
          if (COUNT_LIKE.test(match[1]!)) hits.push(`${file}:${lineOf(source, match.index)} ${match[0]}`);
        }
      }
    }
    expect(hits).toEqual([]);
  });
});
