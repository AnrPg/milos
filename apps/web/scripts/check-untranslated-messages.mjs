import fs from "node:fs";
import path from "node:path";

const locales = ["el", "ar", "ru", "de", "es", "pt-PT", "he", "it", "bg", "nl", "fr"];
const messagesDir = path.resolve("messages");

function flatten(value, prefix = "") {
  return Object.entries(value).flatMap(([key, child]) => {
    const next = prefix ? `${prefix}.${key}` : key;
    return child && typeof child === "object" && !Array.isArray(child)
      ? flatten(child, next)
      : [[next, child]];
  });
}

function normalize(value) {
  return value
    .replace(/\{[^}]+\}/g, "")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim()
    .toLocaleLowerCase("en");
}

function hasEnglishProseShape(value) {
  const normalized = normalize(value);
  const words = normalized.split(" ").filter(Boolean);

  return words.length >= 3 && /[a-z]/.test(normalized);
}

function isUtilityClassToken(token) {
  const normalized = token.replace(/^(?:sm|md|lg|xl|2xl|hover|focus|focus-visible|active|disabled|group-hover|group-focus-visible):/, "");

  return /^(?:flex|grid|block|inline|hidden|relative|absolute|overflow|truncate)$/.test(normalized)
    || /^(?:min-|max-)?(?:h|w)-[\w./-]+$/.test(normalized)
    || /^(?:m|mx|my|ms|me|mt|mr|mb|ml|p|px|py|ps|pe|pt|pr|pb|pl|gap)-[-\w./]+$/.test(normalized)
    || /^(?:items|justify|place|self)-[\w-]+$/.test(normalized)
    || /^(?:flex|grid|shrink|grow)-[\w./-]+$/.test(normalized)
    || /^(?:rounded|border|outline|ring|shadow|object)-[\w./-]+$/.test(normalized)
    || /^(?:bg|text|font|leading|tracking|whitespace)-[\w./[\]()-]+$/.test(normalized);
}

function isUtilityClassList(value) {
  const tokens = value.trim().split(/\s+/).filter(Boolean);
  return tokens.length > 1 && tokens.every(isUtilityClassToken);
}

function isAllowedSharedValue(value) {
  const trimmed = value.trim();

  return trimmed === ""
    || /^[A-Z0-9_+./ -]+$/.test(trimmed)
    || /^(?:TrainingJournal|Milos Training|CrossFit|Rx|Rx\+|AMRAP|EMOM|RFT|PR|URL|VAPID)$/i.test(trimmed)
    || /^https?:\/\//.test(trimmed)
    || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed)
    || /^\/[\w/?=&.-]*$/.test(trimmed)
    || /^[\w.+-]+\/[\w.+-]+$/.test(trimmed)
    || /^\{[^}]+\}$/.test(trimmed)
    || isUtilityClassList(trimmed);
}

const english = new Map(
  flatten(JSON.parse(fs.readFileSync(path.join(messagesDir, "en.json"), "utf8"))),
);
const failures = [];

for (const locale of locales) {
  const entries = new Map(
    flatten(JSON.parse(fs.readFileSync(path.join(messagesDir, `${locale}.json`), "utf8"))),
  );

  for (const [key, englishValue] of english.entries()) {
    const localizedValue = entries.get(key);
    if (typeof englishValue !== "string" || typeof localizedValue !== "string") continue;
    if (!hasEnglishProseShape(englishValue) || isAllowedSharedValue(englishValue)) continue;
    if (normalize(englishValue) === normalize(localizedValue)) {
      failures.push(`${locale}: ${key} still matches English: ${JSON.stringify(localizedValue)}`);
    }
  }
}

if (failures.length > 0) {
  console.error("Untranslated non-English catalog messages found:\n");
  console.error(failures.join("\n"));
  process.exit(1);
}

console.log(`No unchanged English prose found across ${locales.length} non-English catalogs.`);
