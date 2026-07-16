import fs from "node:fs";
import path from "node:path";

const messagesDir = path.resolve("messages");
const targets = {el: "el", ar: "ar", ru: "ru", de: "de", es: "es", "pt-PT": "pt", he: "iw", it: "it", bg: "bg", nl: "nl", fr: "fr"};
const english = JSON.parse(fs.readFileSync(path.join(messagesDir, "en.json"), "utf8"));

function flatten(value, prefix = "") {
  return Object.entries(value).flatMap(([key, child]) => {
    const next = prefix ? `${prefix}.${key}` : key;
    return child && typeof child === "object" && !Array.isArray(child) ? flatten(child, next) : [[next, child]];
  });
}

function setPath(object, key, value) {
  const parts = key.split(".");
  const leaf = parts.pop();
  const parent = parts.reduce((current, part) => current[part], object);
  parent[leaf] = value;
}

function protect(message) {
  const names = [...new Set([...message.matchAll(/\{\s*([A-Za-z_][\w]*)\s*\}/g)].map((match) => match[1]))];
  return {
    names,
    message: message.replace(/\{\s*([A-Za-z_][\w]*)\s*\}/g, (_, name) => `{${names.indexOf(name)}}`),
  };
}

function restore(message, names) {
  const found = [...message.matchAll(/\{(\d+)\}/g)].map((match) => Number(match[1])).sort();
  const expected = [...protect(englishPlaceholderTemplate(names)).message.matchAll(/\{(\d+)\}/g)]
    .map((match) => Number(match[1])).sort();
  if (!names.every((_, index) => found.includes(index))) throw new Error(`protected placeholders missing: expected ${expected}, found ${found}`);
  return message.replace(/\{(\d+)\}/g, (_, index) => `{${names[Number(index)]}}`);
}

function englishPlaceholderTemplate(names) {
  return names.map((name) => `{${name}}`).join(" ");
}

async function translate(message, locale) {
  const url = new URL("https://translate.googleapis.com/translate_a/single");
  for (const [key, value] of Object.entries({client: "gtx", sl: "en", tl: locale, dt: "t", q: message})) url.searchParams.set(key, value);
  const response = await fetch(url);
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  const payload = await response.json();
  return payload[0].map((segment) => segment[0]).join("").trim();
}

const parameterized = flatten(english).filter(([, message]) => /\{\s*[A-Za-z_][\w]*\s*\}/.test(message));

for (const [catalogLocale, translationLocale] of Object.entries(targets)) {
  const filename = path.join(messagesDir, `${catalogLocale}.json`);
  const catalog = JSON.parse(fs.readFileSync(filename, "utf8"));
  let completed = 0;
  for (const [key, message] of parameterized) {
    const protectedMessage = protect(message);
    let translated;
    let lastError;
    for (let attempt = 1; attempt <= 4; attempt += 1) {
      try {
        translated = restore(await translate(protectedMessage.message, translationLocale), protectedMessage.names);
        break;
      } catch (error) {
        lastError = error;
      }
    }
    if (!translated) throw new Error(`${catalogLocale}:${key}: ${lastError?.message}`);
    setPath(catalog, key, translated);
    completed += 1;
    process.stdout.write(`\r${catalogLocale}: ${completed}/${parameterized.length}`);
  }
  fs.writeFileSync(filename, `${JSON.stringify(catalog, null, 2)}\n`);
  process.stdout.write("\n");
}
