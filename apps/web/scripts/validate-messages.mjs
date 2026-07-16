import fs from "node:fs";
import path from "node:path";

const locales = ["en", "el", "ar", "ru", "de", "es", "pt-PT", "he", "it", "bg", "nl", "fr"];
const messagesDir = path.resolve("messages");

function flatten(value, prefix = "") {
  return Object.entries(value).flatMap(([key, child]) => {
    const next = prefix ? `${prefix}.${key}` : key;
    return child && typeof child === "object" && !Array.isArray(child)
      ? flatten(child, next)
      : [[next, child]];
  });
}

const reference = new Map(
  flatten(JSON.parse(fs.readFileSync(path.join(messagesDir, "en.json"), "utf8"))),
);
const failures = [];

for (const locale of locales) {
  const filename = path.join(messagesDir, `${locale}.json`);
  if (!fs.existsSync(filename)) {
    failures.push(`${locale}: catalog is missing`);
    continue;
  }

  const entries = new Map(flatten(JSON.parse(fs.readFileSync(filename, "utf8"))));

  for (const key of reference.keys()) {
    if (!entries.has(key)) failures.push(`${locale}: missing ${key}`);
    if (typeof entries.get(key) !== "string" || entries.get(key).trim() === "") {
      failures.push(`${locale}: ${key} must be a non-empty string`);
    }
  }

  for (const key of entries.keys()) {
    if (!reference.has(key)) failures.push(`${locale}: unexpected ${key}`);
  }
}

if (failures.length > 0) {
  console.error(failures.join("\n"));
  process.exit(1);
}

console.log(`Validated ${reference.size} messages across ${locales.length} locales.`);
