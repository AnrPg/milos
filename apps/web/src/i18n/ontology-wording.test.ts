import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

// docs/product/ontology.md §1: Greek never shows "PT" or "squad", roles name
// the person (not the department), and a member always says what of.
const locales = ["en", "el", "ar", "ru", "de", "es", "pt-PT", "he", "it", "bg", "nl", "fr"];
const ROLE_KEYS = ["roleOwner", "roleAdmin", "roleCoach", "roleFrontDesk", "roleAccountant", "roleJanitor", "roleMember", "roleAthlete"];

function catalog(locale: string) {
  return JSON.parse(fs.readFileSync(path.resolve("messages", `${locale}.json`), "utf8")) as Record<string, unknown>;
}

// ontology §4.8: words that must never name a class (or a trial) in each locale.
// `(?<!\p{L})` / `(?!\p{L})` are letter boundaries that also work for Greek,
// Cyrillic, Arabic and Hebrew, where `\b` does not.
const B = "(?<!\\p{L})";
const E = "(?!\\p{L})";
const BANNED: Record<string, string> = {
  el: `κουλοχ|${B}[μΜ][αά]θ[ηή]μ(α|ατα|ατος|άτων)${E}|${B}[τΤ]άξ(η|ης|εις|εων)${E}|${B}[κΚ]λάσ(η|ης|εις|εων)${E}|${B}[δΔ]ίκ(η|ης|ες)${E}`,
  ar: `${B}(ال)?فصول?${E}|${B}(ال)?صفوف${E}|${B}الطبقة${E}|فتح[ةا]ت?${E}|ماكينة القمار|آلة القمار`,
  ru: `(?<![мМ]астер-)[кК]ласс(?!иф|ическ|ик|н)|${B}[уУ]рок|[сС]лот|игров(ой|ые) автомат`,
  de: `[kK]lasse(?!ment)|Klassen|[sS]lot|Spielautomat|Steckplatz`,
  es: `ranura|tragaperras|tragamonedas|${B}espacio de clase`,
  "pt-PT": `[tT]urma|[cC]lasse|${B}slot|caça-níqueis|ranhura`,
  he: `כית[הו]ת?|משבצ|מכונת מזל`,
  it: `${B}[cC]lass[ie]${E}|${B}slot${E}|[sS]lot machine`,
  bg: `${B}[кК]лас(ове|а|ът)?${E}|[сС]лот|ротатив|игрален автомат`,
  nl: `${B}[kK]las(se)?${E}|[kK]lassen|[sS]leuf|gokkast|${B}[sS]lot`,
  fr: `${B}[cC]lasses?${E}|[eE]mplacement de cours|machine à sous`,
};

/** Text without ICU placeholders such as `{slot}`, which are code, not words. */
function words(text: string): string {
  let previous = "";
  let current = text;
  while (current !== previous) {
    previous = current;
    current = current.replace(/\{[^{}]*\}/g, " ");
  }
  return current;
}

function strings(node: unknown): string[] {
  if (typeof node === "string") return [node];
  if (node && typeof node === "object") return Object.values(node).flatMap(strings);
  return [];
}

describe("canonical wording", () => {
  it("never writes PT or squad in Greek", () => {
    const offending = strings(catalog("el")).filter((text) => /\bPT\b|squad/i.test(text));
    expect(offending).toEqual([]);
  });

  it("labels every role in every locale", () => {
    for (const locale of locales) {
      const ui = catalog(locale).Ui as Record<string, string>;
      for (const key of ROLE_KEYS) expect(ui[key], `${locale}.${key}`).toBeTruthy();
    }
  });

  it("uses person words for Greek roles and a qualified member", () => {
    const ui = catalog("el").Ui as Record<string, string>;
    expect(ui.roleJanitor).toBe("Προσωπικό καθαριότητας");
    expect(ui.roleAccountant).toBe("Λογιστής");
    expect(ui.roleMember).not.toBe("Μέλος");
  });

  it.each(Object.keys(BANNED))("never names a class with a banned word in %s", (locale) => {
    const banned = new RegExp(BANNED[locale], "u");
    const offending = strings(catalog(locale)).filter((text) => banned.test(words(text)));
    expect(offending).toEqual([]);
  });

  it("uses the canonical class terms on the recurring-class form", () => {
    const expected: Record<string, [string, string]> = {
      en: ["New recurring class", "Class start time"],
      el: ["Νέο επαναλαμβανόμενο τμήμα", "Ώρα έναρξης τμήματος"],
      de: ["Neuer wiederkehrender Kurs", "Kursbeginn"],
      fr: ["Nouveau cours récurrent", "Heure de début du cours"],
      es: ["Nueva clase recurrente", "Hora de inicio de la clase"],
      it: ["Nuova lezione ricorrente", "Ora di inizio della lezione"],
      ru: ["Новое повторяющееся занятие", "Время начала занятия"],
    };
    for (const [locale, [series, startTime]] of Object.entries(expected)) {
      const ui = catalog(locale).Ui as Record<string, string>;
      expect(ui.featureCreateClassSeries, locale).toBe(series);
      expect(ui.featureTime, locale).toBe(startTime);
    }
  });

  it("calls the trial package type a trial and packages subscription packages in Greek", () => {
    const ui = catalog("el").Ui as Record<string, string>;
    expect(ui.pkgTypeTrial).toBe("Δοκιμαστικό");
    expect(ui.trial5f7537c).toBe("Δοκιμαστικό");
    expect(ui.package7431e3d).toBe("Πακέτο συνδρομής");
    expect((catalog("en").Ui as Record<string, string>).package7431e3d).toBe("Subscription package");
  });
  it("names the Finance tab «Εκκρεμότητες» (pending items) the same everywhere", () => {
    // ontology §4.17: one name per locale for the tab, the hint that points to it and its lists.
    const pendingItems: Record<string, string> = {
      en: "Pending items",
      el: "Εκκρεμότητες",
      de: "Offene Punkte",
      fr: "Éléments en attente",
      es: "Pendientes",
      it: "Voci in sospeso",
      nl: "Openstaande zaken",
      "pt-PT": "Pendentes",
      ru: "Незавершённые дела",
      bg: "Висящи въпроси",
      ar: "العناصر المعلقة",
      he: "פריטים ממתינים",
    };
    const oldName = /Ουρ[έά]ς|Queues|Arbeitslisten|Files de traitement|Colas|Code operative|[wW]achtrij|Filas|[оО]черед|[оО]пашк|طوابير|قوائم الانتظار|תורים/u;
    for (const locale of locales) {
      const messages = catalog(locale);
      const ui = messages.Ui as Record<string, string>;
      const hint = (messages.OnlinePayments as Record<string, string>).notifyStaffHint;
      expect(ui.queues83dbc32, locale).toBe(pendingItems[locale]);
      expect(ui.operationalQueuesc2120a9, locale).toBe(pendingItems[locale]);
      expect(hint, locale).toContain(`› ${pendingItems[locale]}`);
      for (const key of ["loadingQueuea1e2a39", "noItemsInThisQueuec992fc9", "manageMembersPackagesPromotionsReferralsAndOperationalQueues9eab02d"]) {
        expect(ui[key], `${locale}.${key}`).not.toMatch(oldName);
      }
    }
  });
  it("names an interval's work phase with the gym word of each locale, the same everywhere", () => {
    // ontology §4.8: the timer's work phase (Work / Rest), never a job or an on/off switch.
    const work: Record<string, string> = {
      en: "Work",
      el: "Άσκηση",
      de: "Belastung",
      fr: "Effort",
      es: "Trabajo",
      it: "Lavoro",
      ru: "Работа",
      ar: "تمرين",
      he: "עבודה",
      bg: "Работа",
      nl: "Inspanning",
      "pt-PT": "Trabalho",
    };
    const switchWords = /[δΔ]ουλει|ein\/aus|\b(an|aus|aan|uit|ligado|desligado)\b|تشغيل|إيقاف|מופעל|כבוי|הנחה|включени|изключени|الموارد البشرية|משאבי אנוש|RH|HR-verdieping|етаж/u;
    for (const locale of locales) {
      const messages = catalog(locale);
      const ui = messages.Ui as Record<string, string>;
      const plan = messages.PlanCore as { param: Record<string, string> };
      const editor = messages.PlanEditor as Record<string, string>;
      expect(ui.workPhaseLabel, locale).toBe(work[locale]);
      expect(ui.work00040ba, locale).toBe(work[locale]);
      expect(plan.param.work, locale).toBe(work[locale]);
      expect(editor.timelineWork, locale).toBe(work[locale]);
      expect(ui.timerLabelWork, locale).toBe(`${work[locale]} {round}/{total}`);
      for (const key of ["instructionTabata", "instructionCustomHiit", "instructionHrr", "hrCeilingStopWork3e9d698", "hrFloorResumeWork82d77a0", "workSecondsLabel"]) {
        expect(words(ui[key]), `${locale}.${key}`).not.toMatch(switchWords);
      }
    }
  });
});
