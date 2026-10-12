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

// Collects ICU argument names. Branch bodies of plural/select arguments
// (`one {seat}`) are message text, so they are parsed as nested messages
// rather than read as placeholders.
function placeholders(message) {
  const names = [];
  let index = 0;

  const parseMessage = (stopAtBrace) => {
    while (index < message.length) {
      const char = message[index];
      if (char === "{") {
        index += 1;
        parseArgument();
      } else if (char === "}" && stopAtBrace) {
        index += 1;
        return;
      } else {
        index += 1;
      }
    }
  };

  const readUntil = (stops) => {
    const begin = index;
    while (index < message.length && !stops.includes(message[index])) index += 1;
    return message.slice(begin, index).trim();
  };

  const parseArgument = () => {
    const name = readUntil([",", "}"]);
    if (/^[A-Za-z_]\w*$/.test(name)) names.push(name);
    if (message[index] === "}") {
      index += 1;
      return;
    }
    index += 1;
    const type = readUntil([",", "}"]);
    if (message[index] === "}") {
      index += 1;
      return;
    }
    index += 1;
    if (!["plural", "select", "selectordinal"].includes(type)) {
      readUntil(["}"]);
      index += 1;
      return;
    }
    while (index < message.length) {
      readUntil(["{", "}"]);
      if (message[index] === "}") {
        index += 1;
        return;
      }
      index += 1;
      parseMessage(true);
    }
  };

  parseMessage(false);
  return names.sort();
}

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
    } else {
      const expected = placeholders(reference.get(key));
      const actual = placeholders(entries.get(key));
      if (expected.join("\0") !== actual.join("\0")) {
        failures.push(`${locale}: ${key} placeholders differ (expected ${expected.join(", ") || "none"}; found ${actual.join(", ") || "none"})`);
      }
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
