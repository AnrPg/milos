


import {getUiTranslations} from "@/i18n/ui-server";

import {useUiTranslations} from "@/i18n/ui";
import type {Metadata} from "next";
import Link from "next/link";

export async function generateMetadata(): Promise<Metadata> {
  const i18n = await getUiTranslations();
  return {
    title: i18n("aboutMilosTrainingac8164e"),
    description: i18n("howMilosTrainingSupportsMembersAthletesAndCoaches7fc09dd"),
  };
}

export default function AboutPage() {
  const i18n = useUiTranslations();
  return (
    <main className="mx-auto w-full max-w-4xl flex-1 px-6 py-16" style={{ color: "var(--text)" }}>
      <p className="text-sm font-semibold uppercase tracking-[0.24em]" style={{ color: "var(--primary)" }}>
        {i18n("trainWithIntent94cee47")}
      </p>
      <h1 className="mt-3 text-4xl font-bold tracking-tight sm:text-6xl">{i18n("milosTraining5b1a1c1")}</h1>
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
        <Link className="rounded-xl px-5 py-3 font-semibold" style={{ background: "var(--primary)", color: "var(--bg)" }} href="/register">
          {i18n("createAnAccount3f4f547")}
        </Link>
        <Link className="rounded-xl border px-5 py-3 font-semibold" style={{ borderColor: "var(--border)" }} href="/login">
          {i18n("signInada2e9e")}
        </Link>
      </div>
    </main>
  );
}
