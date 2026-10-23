import { describe, expect, it } from "vitest";

import { faqStructuredData, llmsText, serializeJsonLd, siteStructuredData } from "./site-info";

const facts = {
  origin: new URL("https://palee.example"),
  description: "One home for gym training.",
  features: ["Members: book classes"],
  languages: ["en", "el"] as const,
};
const faq = [{ question: "What is Palee?", answer: "A training platform." }];

describe("site info", () => {
  it("links the organization, website and app in one graph with absolute URLs", () => {
    const graph = siteStructuredData(facts)["@graph"];
    expect(graph.map((node) => node["@type"])).toEqual(["Organization", "WebSite", "WebApplication"]);
    expect(graph[0]).toMatchObject({ name: "Palee", url: "https://palee.example/", logo: "https://palee.example/icon.svg" });
    expect(graph[2]).toMatchObject({ publisher: { "@id": "https://palee.example/#organization" }, inLanguage: ["en", "el"] });
  });

  it("builds FAQPage questions with accepted answers", () => {
    expect(faqStructuredData(faq).mainEntity).toEqual([
      { "@type": "Question", name: "What is Palee?", acceptedAnswer: { "@type": "Answer", text: "A training platform." } },
    ]);
  });

  it("writes llms.txt with the summary, absolute page links and the FAQ", () => {
    const text = llmsText(facts, faq);
    expect(text.startsWith("# Palee\n\n> One home for gym training.\n")).toBe(true);
    expect(text).toContain("- [About Palee](https://palee.example/about)");
    expect(text).toContain("### What is Palee?\n\nA training platform.");
  });

  it("cannot close the script tag it is embedded in", () => {
    expect(serializeJsonLd({ text: "</script><script>alert(1)</script>" })).not.toContain("</script>");
  });
});
