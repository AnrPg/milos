"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";

import { InterestsEditor } from "@/components/interests/InterestsEditor";
import { BackToMe } from "@/components/member-app/me/BackToMe";

/** Εγώ › Ρυθμίσεις › «Τι κάνεις» (ADR-183): the first-run's step 2, any time later. */
export function InterestsSettingsPage() {
  const t = useTranslations("FirstRun");
  const [saved, setSaved] = useState(false);

  return (
    <main className="min-h-screen px-4 py-6 md:px-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-2xl flex-col gap-4">
        <BackToMe />
        <header className="flex flex-col gap-1">
          <h1 className="text-xl font-extrabold" style={{ color: "var(--text)" }}>{t("interestsTitle")}</h1>
          <p className="text-sm leading-6" style={{ color: "var(--text-soft)" }}>{t("interestsLead")}</p>
        </header>
        <InterestsEditor
          onSaved={() => setSaved(true)}
          renderActions={({ save, busy, dirty }) => (
            <div className="flex flex-col gap-2">
              <button
                type="button"
                onClick={save}
                disabled={busy || !dirty}
                className="min-h-12 w-full rounded-2xl px-4 text-sm font-bold disabled:opacity-60"
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              >
                {t("saveInterests")}
              </button>
              {saved && !dirty ? (
                <p role="status" className="text-sm font-semibold" style={{ color: "var(--success)" }}>{t("interestsSaved")}</p>
              ) : null}
            </div>
          )}
        />
      </div>
    </main>
  );
}
