"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import { HubButton } from "@/components/member-app/HubParts";

import { myMissingCount } from "./documents-model";
import { useMyDocuments } from "./use-documents";

/**
 * Box › «Λείπουν N έγγραφα» (mockup s7, option B): one card at the top of
 * Box, shown only while something mandatory is missing (vision §4 principle
 * 2: a card with nothing in it is hidden), gone once everything is signed.
 */
export function DocumentsBoxCard() {
  const t = useTranslations("Documents");
  const overview = useMyDocuments();
  const missing = myMissingCount(overview.data);
  if (missing === 0) return null;

  return (
    <Link
      href="/box/documents"
      data-testid="box-documents-card"
      className="flex items-center gap-3 rounded-3xl px-5 py-4"
      style={{
        background: "color-mix(in srgb, var(--warning) 12%, var(--panel))",
        border: "1px solid color-mix(in srgb, var(--warning) 45%, transparent)",
        color: "var(--text)",
      }}
    >
      <span aria-hidden="true" className="text-xl">
        📄
      </span>
      <span className="flex min-w-0 flex-1 flex-col">
        <b className="text-sm">{t("boxCardTitle", { count: missing })}</b>
        <span className="text-xs" style={{ color: "var(--text-soft)" }}>
          {t("boxCardBody")}
        </span>
      </span>
      <span aria-hidden="true" style={{ color: "var(--dim)" }}>
        ›
      </span>
    </Link>
  );
}

/** «Έγγραφα» in the Συνδρομή card, only when the box has documents for the client. */
export function DocumentsButton() {
  const t = useTranslations("Documents");
  const overview = useMyDocuments();
  const data = overview.data;
  const has = Boolean(data && (data.documents.some((item) => item.current_version_id) || data.health_certificate.required || data.health_certificate.certificate));
  if (!has) return null;
  return <HubButton href="/box/documents">{t("title")}</HubButton>;
}
