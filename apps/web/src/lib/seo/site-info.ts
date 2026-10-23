// What search engines and AI answer engines are told about Palee: the JSON-LD
// graph, the FAQ and llms.txt are all built from these pure functions, so the
// facts stay identical across every surface.

export const BRAND_NAME = "Palee";

export type FaqEntry = { question: string; answer: string };

export type FeatureFacts = { title: string; summary: string; details: string[] };

export type SiteFacts = {
  origin: URL;
  description: string;
  // Who Palee is for: the business side and the social side in one app.
  overview: string[];
  features: FeatureFacts[];
  languages: readonly string[];
};

export const FAQ_KEYS = [
  ["whatIsQuestion", "whatIsAnswer"],
  ["twoSidesQuestion", "twoSidesAnswer"],
  ["whoForQuestion", "whoForAnswer"],
  ["eventsQuestion", "eventsAnswer"],
  ["offlineQuestion", "offlineAnswer"],
  ["adsQuestion", "adsAnswer"],
  ["languagesQuestion", "languagesAnswer"],
] as const;

export const PUBLIC_PAGES = [
  { path: "/about", title: "About Palee" },
  { path: "/register", title: "Create an account" },
  { path: "/register/business", title: "Register a gym or coaching business" },
  { path: "/login", title: "Sign in" },
] as const;

function absolute(path: string, origin: URL) {
  return new URL(path, origin).toString();
}

export function siteStructuredData({ origin, description, features, languages }: SiteFacts) {
  const home = absolute("/", origin);
  const organizationId = `${home}#organization`;
  return {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "Organization",
        "@id": organizationId,
        name: BRAND_NAME,
        url: home,
        logo: absolute("/icon.svg", origin),
      },
      {
        "@type": "WebSite",
        "@id": `${home}#website`,
        name: BRAND_NAME,
        url: home,
        description,
        inLanguage: [...languages],
        publisher: { "@id": organizationId },
      },
      {
        "@type": "WebApplication",
        "@id": `${home}#app`,
        name: BRAND_NAME,
        url: home,
        description,
        applicationCategory: "HealthApplication",
        applicationSubCategory: "Gym management and training",
        operatingSystem: "Web",
        browserRequirements: "Requires JavaScript",
        inLanguage: [...languages],
        featureList: features.map(({ title, summary }) => `${title}: ${summary}`),
        publisher: { "@id": organizationId },
      },
    ],
  };
}

export function faqStructuredData(entries: FaqEntry[]) {
  return {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: entries.map(({ question, answer }) => ({
      "@type": "Question",
      name: question,
      acceptedAnswer: { "@type": "Answer", text: answer },
    })),
  };
}

// https://llmstxt.org: a Markdown map of the site for language models.
export function llmsText({ origin, description, overview, features }: SiteFacts, faq: FaqEntry[]) {
  return [
    `# ${BRAND_NAME}`,
    "",
    `> ${description}`,
    "",
    ...overview.flatMap((paragraph) => [paragraph, ""]),
    "## Features",
    "",
    ...features.flatMap(({ title, summary, details }) => [
      `### ${title}`,
      "",
      summary,
      "",
      ...details.map((detail) => `- ${detail}`),
      "",
    ]),
    "## Pages",
    "",
    ...PUBLIC_PAGES.map(({ path, title }) => `- [${title}](${absolute(path, origin)})`),
    "",
    "## FAQ",
    "",
    ...faq.flatMap(({ question, answer }) => [`### ${question}`, "", answer, ""]),
  ].join("\n");
}

// JSON inside <script> must not be able to close the tag.
export function serializeJsonLd(data: unknown) {
  return JSON.stringify(data).replace(/</g, "\\u003c");
}
