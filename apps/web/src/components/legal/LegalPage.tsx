import Link from "next/link";
import type { ReactNode } from "react";
import { getFormatter, getTranslations } from "next-intl/server";

/** ADR-267: the date of the draft both texts show until the law consultant signs them off. */
export const LEGAL_DRAFT_DATE = "2026-10-29";

/** The values the legal adviser fills in; until then each shows as a visible "[…]" placeholder. */
export async function legalPlaceholders() {
  const t = await getTranslations("legal");
  return {
    controller: t("placeholderController"),
    address: t("placeholderAddress"),
    contact: t("placeholderContact"),
    authority: t("placeholderAuthority"),
    law: t("placeholderLaw"),
  };
}

/** The frame of /privacy and /terms: title, draft notice, sections, links between the two. */
export async function LegalPage({
  title,
  intro,
  current,
  children,
}: {
  title: string;
  intro: string;
  current: "privacy" | "terms";
  children: ReactNode;
}) {
  const t = await getTranslations("legal");
  const format = await getFormatter();
  const linkStyle = { color: "var(--primary)" } as const;

  return (
    <main className="flex w-full flex-1">
      <article className="mx-auto w-full max-w-3xl flex-1 px-4 py-10 sm:px-6 sm:py-14" style={{ color: "var(--text)" }}>
        <p
          className="rounded-2xl px-4 py-3 text-sm leading-6"
          role="note"
          style={{ background: "var(--panel-muted)", border: "1px solid var(--warning)", color: "var(--text)" }}
        >
          <strong className="me-1">{t("draftLabel")}</strong>
          {t("draftNotice")}
        </p>
        <h1 className="mt-8 text-3xl font-bold tracking-tight sm:text-4xl">{title}</h1>
        <p className="mt-2 text-sm" style={{ color: "var(--dim)" }}>
          {t("lastUpdated", { date: format.dateTime(new Date(`${LEGAL_DRAFT_DATE}T12:00:00Z`), { dateStyle: "long" }) })}
        </p>
        <p className="mt-6 leading-7" style={{ color: "var(--muted)" }}>
          {intro}
        </p>
        <div className="mt-8 space-y-10">{children}</div>
        <nav
          aria-label={t("footerLabel")}
          className="mt-14 flex flex-wrap gap-x-6 gap-y-2 border-t pt-6 text-sm"
          style={{ borderColor: "var(--border)" }}
        >
          {current === "privacy" ? (
            <Link href="/terms" className="font-semibold" style={linkStyle}>
              {t("termsTitle")}
            </Link>
          ) : (
            <Link href="/privacy" className="font-semibold" style={linkStyle}>
              {t("privacyTitle")}
            </Link>
          )}
          <Link href="/about" className="font-semibold" style={linkStyle}>
            {t("aboutLink")}
          </Link>
        </nav>
      </article>
    </main>
  );
}

/** One titled section of a legal text. */
export function LegalSection({ id, title, children }: { id: string; title: string; children: ReactNode }) {
  return (
    <section id={id} aria-labelledby={`${id}-title`} className="scroll-mt-20">
      <h2 id={`${id}-title`} className="text-xl font-semibold tracking-tight">
        {title}
      </h2>
      <div className="mt-3 space-y-3 leading-7" style={{ color: "var(--muted)" }}>
        {children}
      </div>
    </section>
  );
}

/** A plain list of sentences inside a section. */
export function LegalList({ items }: { items: string[] }) {
  return (
    <ul className="list-disc space-y-2 ps-5">
      {items.map((item) => (
        <li key={item}>{item}</li>
      ))}
    </ul>
  );
}
