import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";

import { LegalList, LegalPage, LegalSection, legalPlaceholders } from "@/components/legal/LegalPage";
import { SEPARATE_CONTROLLERS, SUB_PROCESSORS } from "@/lib/legal/sub-processors";

export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations("legal");
  const title = t("privacyTitle");
  const description = t("privacy.intro");
  return {
    title,
    description,
    alternates: { canonical: "/privacy" },
    openGraph: { title, description, url: "/privacy" },
  };
}

const DATA_KEYS = [
  "dataAccount",
  "dataProfile",
  "dataBookings",
  "dataTraining",
  "dataWellness",
  "dataHealth",
  "dataMessages",
  "dataPayments",
  "dataDocuments",
  "dataLocation",
  "dataTechnical",
] as const;
const PURPOSE_KEYS = ["purposeContract", "purposeLegal", "purposeConsent", "purposeSecurity"] as const;
const RETENTION_KEYS = ["retentionAccount", "retentionBox", "retentionFiscal", "retentionExport", "retentionBackups"] as const;
const RIGHT_KEYS = ["rightAccess", "rightRectification", "rightErasure", "rightConsent"] as const;

/** ADR-267: Palee's privacy policy (GDPR articles 13 and 14), a draft for the law consultant. */
export default async function PrivacyPage() {
  const t = await getTranslations("legal");
  const p = await getTranslations("legal.privacy");
  const values = await legalPlaceholders();
  const cell = "px-3 py-2 align-top";

  return (
    <LegalPage title={t("privacyTitle")} intro={p("intro")} current="privacy">
      <LegalSection id="controller" title={p("controllerTitle")}>
        <p>{p("controllerBody", values)}</p>
        <p>{p("boxRoleBody")}</p>
      </LegalSection>

      <LegalSection id="data" title={p("dataTitle")}>
        <LegalList items={DATA_KEYS.map((key) => p(key))} />
        <p>{p("dataNotCollected")}</p>
      </LegalSection>

      <LegalSection id="purposes" title={p("purposesTitle")}>
        <LegalList items={PURPOSE_KEYS.map((key) => p(key))} />
      </LegalSection>

      <LegalSection id="health" title={p("healthTitle")}>
        <p>{p("healthBody")}</p>
      </LegalSection>

      <LegalSection id="sub-processors" title={p("recipientsTitle")}>
        <p>{p("recipientsIntro")}</p>
        {/* Focusable so keyboard users can scroll the table on narrow screens (axe scrollable-region-focusable).
            A group, not a region: the section is already the landmark with this name (axe landmark-unique). */}
        <div
          role="group"
          aria-label={p("recipientsTitle")}
          tabIndex={0}
          className="overflow-x-auto rounded-2xl border"
          style={{ borderColor: "var(--border)" }}
        >
          <table className="w-full min-w-[32rem] text-start text-sm">
            <thead style={{ background: "var(--panel-muted)", color: "var(--text)" }}>
              <tr>
                <th scope="col" className={`${cell} text-start font-semibold`}>
                  {p("columnService")}
                </th>
                <th scope="col" className={`${cell} text-start font-semibold`}>
                  {p("columnPurpose")}
                </th>
                <th scope="col" className={`${cell} text-start font-semibold`}>
                  {p("columnWebsite")}
                </th>
              </tr>
            </thead>
            <tbody>
              {SUB_PROCESSORS.map((processor) => (
                <tr key={processor.id} className="border-t" style={{ borderColor: "var(--border)" }}>
                  <td className={cell} style={{ color: "var(--text)" }}>
                    {processor.id === "hosting" ? t("placeholderHosting") : processor.name}
                  </td>
                  <td className={cell}>
                    {p(processor.purpose)}
                    {processor.boxFeature ? ` ${p("boxFeatureNote")}` : ""}
                  </td>
                  <td className={cell} dir="ltr">
                    {processor.id === "hosting" ? t("placeholderHosting") : processor.host}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {SEPARATE_CONTROLLERS.map((controller) => (
          <p key={controller.id}>{p("separateControllerBody", { name: controller.name })}</p>
        ))}
      </LegalSection>

      <LegalSection id="transfers" title={p("transfersTitle")}>
        <p>{p("transfersBody")}</p>
      </LegalSection>

      <LegalSection id="retention" title={p("retentionTitle")}>
        <LegalList items={RETENTION_KEYS.map((key) => p(key))} />
      </LegalSection>

      <LegalSection id="rights" title={p("rightsTitle")}>
        <p>{p("rightsIntro")}</p>
        <LegalList
          items={[
            ...RIGHT_KEYS.map((key) => p(key)),
            p("rightRestriction", values),
            p("rightComplaint", values),
          ]}
        />
      </LegalSection>

      <LegalSection id="minimum-age" title={p("ageTitle")}>
        <p>{p("ageBody")}</p>
      </LegalSection>

      <LegalSection id="security" title={p("securityTitle")}>
        <p>{p("securityBody")}</p>
      </LegalSection>

      <LegalSection id="changes" title={p("changesTitle")}>
        <p>{p("changesBody")}</p>
      </LegalSection>
    </LegalPage>
  );
}
