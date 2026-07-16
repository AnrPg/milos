import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const targets = { en: "en", el: "el", ar: "ar", ru: "ru", de: "de", es: "es", "pt-PT": "pt", he: "iw", it: "it", bg: "bg", nl: "nl", fr: "fr" };
const domains = {
  notifications: [
    "New booking request", "Booking approved", "Booking rejected", "Booking timed out",
    "Open the schedule to review the latest booking state.", "Workout annotation",
    "A workout annotation needs review.", "Workout changed", "Your coach changed a scheduled workout.",
    "Workout removed", "Your coach removed a scheduled workout.", "Workout rejected", "An athlete",
    "a workout", "%{nickname} rejected %{title}.", "Workout rescheduled",
    "An athlete rescheduled their workout.", "Message from %{nickname}",
    "%{nickname} sent you a message.", "New coach note", "Your coach added a new note.",
    "Challenge completed", "You completed a challenge.", "New message in your workout thread",
    "New message", "You received a new message.", "Milos Training", "You have a new notification.",
    "invoice", "New invoice", "Invoice %{invoice_number} has been issued for your account.",
    "Payment reminder", "You have an outstanding balance of %{amount} due."
  ],
  calendar: [
    "Google Calendar: copy the HTTPS .ics URL, then use Other calendars → From URL.",
    "Apple Calendar: use Subscribe with the webcal:// link for automatic updates.",
    "Outlook: use Add calendar → Subscribe from web and paste the HTTPS .ics URL.",
    "Downloading the .ics file imports a one-off snapshot and will not stay synchronized.",
    "Class: %{name}", "Assigned workout", "Workout: %{title}",
    "Assigned workout in Milos Training.", "Scheduled %{name} class in Milos Training.",
    "Pending", "Approved", "Scheduled", "Milos Training class booking status: %{status}."
  ],
  sharing: [
    "New PR — %{name}: %{score} %{unit} (achieved on %{date})",
    "minutes and seconds", "repetitions", "sets", "kilocalories", "metres", "kilograms"
  ]
};

function protect(message) {
  const names = [...new Set([...message.matchAll(/%\{([A-Za-z_][\w]*)\}/g)].map((match) => match[1]))];
  return { names, text: message.replace(/%\{([A-Za-z_][\w]*)\}/g, (_, name) => `%{${names.indexOf(name)}}`) };
}

function restore(message, names) {
  return message.replace(/%\{(\d+)\}/g, (_, index) => `%{${names[Number(index)]}}`);
}

async function translate(message, locale) {
  if (locale === "en") return message;
  const protectedMessage = protect(message);
  const url = new URL("https://translate.googleapis.com/translate_a/single");
  url.searchParams.set("client", "gtx"); url.searchParams.set("sl", "en");
  url.searchParams.set("tl", locale); url.searchParams.set("dt", "t");
  url.searchParams.set("q", protectedMessage.text);
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Translation failed: ${response.status}`);
  const payload = await response.json();
  return restore(payload[0].map((segment) => segment[0]).join(""), protectedMessage.names);
}

const quote = (value) => JSON.stringify(value).replaceAll("\\u2028", " ").replaceAll("\\u2029", " ");
function catalog(locale, entries) {
  const header = `msgid ""\nmsgstr ""\n"Language: ${locale}\\n"\n"Content-Type: text/plain; charset=UTF-8\\n"\n"Content-Transfer-Encoding: 8bit\\n"\n`;
  return `${header}\n${entries.map(([id, value]) => `msgid ${quote(id)}\nmsgstr ${quote(value)}\n`).join("\n")}`;
}

for (const [locale, target] of Object.entries(targets)) {
  const directory = resolve("priv/gettext", locale === "pt-PT" ? "pt_PT" : locale, "LC_MESSAGES");
  await mkdir(directory, { recursive: true });
  for (const [domain, messages] of Object.entries(domains)) {
    const entries = [];
    for (const message of messages) entries.push([message, await translate(message, target)]);
    await writeFile(resolve(directory, `${domain}.po`), catalog(locale, entries));
  }
  console.log(locale);
}

for (const [domain, messages] of Object.entries(domains)) {
  await writeFile(resolve("priv/gettext", `${domain}.pot`), catalog("en", messages.map((message) => [message, ""])));
}
