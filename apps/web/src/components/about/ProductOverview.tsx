import Link from "next/link";
import { getTranslations } from "next-intl/server";

import { PaleeMark } from "@/components/branding/PaleeMark";
import { getUiTranslations } from "@/i18n/ui-server";
import type { FaqEntry, FeatureFacts } from "@/lib/seo/site-info";

// The public description of Palee: the About page, and what crawlers that do
// not run JavaScript read on the home page. Server-rendered, answer first.
export async function ProductOverview({ faq, features }: { faq: FaqEntry[]; features: FeatureFacts[] }) {
  const i18n = await getUiTranslations();
  const info = await getTranslations("SiteInfo");
  const legal = await getTranslations("legal");
  return (
    <div className="mx-auto w-full max-w-4xl flex-1 px-6 py-16" style={{ color: "var(--text)" }}>
      <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--primary)" }}>
        {i18n("trainWithIntent94cee47")}
      </p>
      <h1 className="mt-3 flex items-center gap-4 text-4xl font-bold tracking-tight sm:text-6xl">
        <PaleeMark className="h-12 w-12 shrink-0 sm:h-16 sm:w-16" />
        {i18n("brandName")}
      </h1>
      <p className="mt-6 max-w-2xl text-lg leading-8" style={{ color: "var(--muted)" }}>
        {i18n("onePrivateSelfHostedHomeForGroupClasses89e3bcd")}
      </p>
      <div className="mt-10 grid gap-4 sm:grid-cols-3">
        {[
          [i18n("members1cb449c"), i18n("bookClassesFollowGymUpdatesAndKeepAttendancec7408d8")],
          [i18n("athletesda22204"), i18n("executeTailoredTrainingWithAStepSynchronisedTimer9c0485e")],
          [i18n("coaches181feb6"), i18n("programCommunicateAndUnderstandTrainingProgressWithoutSurveillance7c67d89")],
        ].map(([title, body]) => (
          <section key={title} className="rounded-2xl border p-5" style={{ borderColor: "var(--border)", background: "var(--surface)" }}>
            <h2 className="font-semibold">{title}</h2>
            <p className="mt-2 text-sm leading-6" style={{ color: "var(--muted)" }}>{body}</p>
          </section>
        ))}
      </div>
      <div className="mt-10 flex flex-wrap gap-3">
        <Link className="rounded-xl px-5 py-3 font-semibold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }} href="/register">
          {i18n("createAnAccount3f4f547")}
        </Link>
        <Link className="rounded-xl border px-5 py-3 font-semibold" style={{ borderColor: "var(--border)" }} href="/login">
          {i18n("signInada2e9e")}
        </Link>
      </div>
      <section className="mt-16" aria-labelledby="palee-features">
        <h2 id="palee-features" className="text-2xl font-bold tracking-tight">{info("featuresTitle")}</h2>
        <p className="mt-3 max-w-2xl leading-7" style={{ color: "var(--muted)" }}>{info("twoSidesSummary")}</p>
        <div className="mt-6 grid gap-4 sm:grid-cols-2">
          {features.map(({ title, summary }) => (
            <section key={title} className="rounded-2xl border p-5" style={{ borderColor: "var(--border)", background: "var(--surface)" }}>
              <h3 className="font-semibold">{title}</h3>
              <p className="mt-2 text-sm leading-6" style={{ color: "var(--muted)" }}>{summary}</p>
            </section>
          ))}
        </div>
      </section>
      <section className="mt-16" aria-labelledby="palee-faq">
        <h2 id="palee-faq" className="text-2xl font-bold tracking-tight">{info("faqTitle")}</h2>
        <dl className="mt-6 grid gap-6">
          {faq.map(({ question, answer }) => (
            <div key={question}>
              <dt className="font-semibold">{question}</dt>
              <dd className="mt-1 leading-7" style={{ color: "var(--muted)" }}>{answer}</dd>
            </div>
          ))}
        </dl>
      </section>
      <nav
        aria-label={legal("footerLabel")}
        className="mt-16 flex flex-wrap gap-x-6 gap-y-2 border-t pt-6 text-sm"
        style={{ borderColor: "var(--border)" }}
      >
        <Link href="/privacy" className="font-semibold" style={{ color: "var(--primary)" }}>
          {legal("privacyTitle")}
        </Link>
        <Link href="/terms" className="font-semibold" style={{ color: "var(--primary)" }}>
          {legal("termsTitle")}
        </Link>
      </nav>
    </div>
  );
}
