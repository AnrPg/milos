import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

const locales = ["en", "el", "ar", "ru", "de", "es", "pt_PT", "he", "it", "bg", "nl", "fr"];
const domains = ["notifications", "calendar", "sharing"];

function entries(source) {
  return new Map(
    [...source.matchAll(/^msgid ("(?:[^"\\]|\\.)*")\nmsgstr ("(?:[^"\\]|\\.)*")$/gm)]
      .map((match) => [JSON.parse(match[1]), JSON.parse(match[2])])
      .filter(([id]) => id !== ""),
  );
}

function placeholders(message) {
  return [...message.matchAll(/%\{([A-Za-z_][\w]*)\}/g)].map((match) => match[1]).sort();
}

for (const domain of domains) {
  const reference = entries(await readFile(resolve("priv/gettext/en/LC_MESSAGES", `${domain}.po`), "utf8"));
  for (const locale of locales) {
    const catalog = entries(await readFile(resolve("priv/gettext", locale, "LC_MESSAGES", `${domain}.po`), "utf8"));
    const missing = [...reference.keys()].filter((id) => !catalog.get(id));
    const extra = [...catalog.keys()].filter((id) => !reference.has(id));
    if (missing.length || extra.length) throw new Error(`${locale}/${domain} key mismatch: missing=${missing} extra=${extra}`);
    for (const [id, value] of catalog) {
      if (JSON.stringify(placeholders(id)) !== JSON.stringify(placeholders(value))) {
        throw new Error(`${locale}/${domain} placeholder mismatch for ${id}`);
      }
    }
  }
  console.log(`Validated ${reference.size} ${domain} messages across ${locales.length} locales.`);
}
