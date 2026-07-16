import fs from "node:fs";
import path from "node:path";

const messagesDir = path.resolve("messages");
const targets = {
  el: "el",
  ar: "ar",
  ru: "ru",
  de: "de",
  es: "es",
  "pt-PT": "pt",
  he: "iw",
  it: "it",
  bg: "bg",
  nl: "nl",
  fr: "fr",
};
const english = JSON.parse(fs.readFileSync(path.join(messagesDir, "en.json"), "utf8"));
const entries = Object.entries(english.Ui ?? {});
const batchSize = 35;

function chunks(values, size) {
  return Array.from({length: Math.ceil(values.length / size)}, (_, index) => values.slice(index * size, (index + 1) * size));
}

function translatedText(payload) {
  return payload[0].map((segment) => segment[0]).join("");
}

async function translateBatch(locale, batch, batchIndex) {
  const markers = batch.slice(0, -1).map((_, index) => `\uE000${batchIndex}_${index}\uE001`);
  const input = batch.map(([, message], index) => index < markers.length ? `${message}\n${markers[index]}\n` : message).join("");
  const url = new URL("https://translate.googleapis.com/translate_a/single");
  url.searchParams.set("client", "gtx");
  url.searchParams.set("sl", "en");
  url.searchParams.set("tl", locale);
  url.searchParams.set("dt", "t");
  url.searchParams.set("q", input);

  let lastError;
  for (let attempt = 1; attempt <= 4; attempt += 1) {
    try {
      const response = await fetch(url);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const output = translatedText(await response.json());
      const markerPattern = new RegExp(`\\s*\\uE000${batchIndex}_(?:${markers.map((_, index) => index).join("|")})\\uE001\\s*`, "g");
      const values = markers.length === 0 ? [output.trim()] : output.split(markerPattern).map((value) => value.trim());
      if (values.length !== batch.length || values.some((value) => value.length === 0)) {
        throw new Error(`expected ${batch.length} messages, received ${values.length}`);
      }
      return values;
    } catch (error) {
      lastError = error;
      await new Promise((resolve) => setTimeout(resolve, attempt * 500));
    }
  }
  console.warn(`\n${locale}: batch ${batchIndex} delimiter parsing failed (${lastError.message}); translating ${batch.length} messages individually.`);
  const values = [];
  for (const [, message] of batch) {
    const singleUrl = new URL("https://translate.googleapis.com/translate_a/single");
    singleUrl.searchParams.set("client", "gtx");
    singleUrl.searchParams.set("sl", "en");
    singleUrl.searchParams.set("tl", locale);
    singleUrl.searchParams.set("dt", "t");
    singleUrl.searchParams.set("q", message);
    const response = await fetch(singleUrl);
    if (!response.ok) throw new Error(`HTTP ${response.status} while translating an individual message`);
    values.push(translatedText(await response.json()).trim());
  }
  return values;
}

for (const [catalogLocale, translationLocale] of Object.entries(targets)) {
  const filename = path.join(messagesDir, `${catalogLocale}.json`);
  const catalog = JSON.parse(fs.readFileSync(filename, "utf8"));
  catalog.Ui ??= {};

  let completed = 0;
  for (const [batchIndex, batch] of chunks(entries, batchSize).entries()) {
    const missing = batch.filter(([key]) => !catalog.Ui[key]);
    if (missing.length > 0) {
      const values = await translateBatch(translationLocale, missing, batchIndex);
      missing.forEach(([key], index) => {
        catalog.Ui[key] = values[index];
      });
    }
    completed += batch.length;
    process.stdout.write(`\r${catalogLocale}: ${completed}/${entries.length}`);
  }
  fs.writeFileSync(filename, `${JSON.stringify(catalog, null, 2)}\n`);
  process.stdout.write("\n");
}
