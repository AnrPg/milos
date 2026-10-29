"use client";

import Link from "next/link";
import { useState } from "react";
import { useTranslations } from "next-intl";

import type { DocumentTemplate } from "@/api/documents";
import { PageHeader, pageHeaderActionClass } from "@/components/PageHeader";
import { StatusText } from "@/components/staff/staff-ui";
import { BackLink } from "@/components/ui/BackLink";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { documentError } from "../document-errors";
import { staffRows, type StaffRow } from "../documents-model";
import { useInvalidateDocuments, useStaffDocuments } from "../use-documents";
import { DocumentPanel } from "./DocumentPanel";
import { HealthPanel } from "./HealthPanel";
import { NewDocumentDialog } from "./NewDocumentDialog";
import { SettingsDialog } from "./SettingsDialog";
import { Hint, Pill } from "./staff-parts";

type Selected = { kind: "document"; id: string } | { kind: "health" } | null;

function iconFor(row: StaffRow) {
  if (row.kind === "health") return "⬆";
  return row.template.kind === "privacy" ? "📄" : "✍";
}

/**
 * Χρήστες › Έγγραφα (mockup s7, option B, with the product owner's change):
 * one list of the box's documents, each with «Λείπουν N» or «Όλοι εντάξει»
 * and whether it blocks booking, plus the health certificate. A row opens
 * its side panel. No members × documents table (option A was overload).
 */
export function DocumentsConsole() {
  const t = useTranslations("Documents");
  const i18n = useUiTranslations();
  const organizationSlug = useOrganizationSlug();
  const { access, templates, outstanding, settings, health } = useStaffDocuments();
  const invalidate = useInvalidateDocuments();
  const [selected, setSelected] = useState<Selected>(null);
  const [newOpen, setNewOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);

  if (access.isLoading) {
    return (
      <Shell>
        <StatusText tone="muted">{t("loading")}</StatusText>
      </Shell>
    );
  }
  if (!access.any) {
    return (
      <Shell>
        <PageHeader title={t("title")} />
        <StatusText tone="muted">{t("noAccess")}</StatusText>
      </Shell>
    );
  }

  const rows = staffRows(
    templates.data ?? [],
    outstanding.data,
    health.data ? { required: health.data.required, rows: health.data.health_certificates } : null,
  );
  const gateOn = settings.data?.block_booking_on_unsigned ?? true;
  const healthBlocks = Boolean(settings.data?.block_booking_on_health_certificate);
  const months = settings.data?.health_certificate_validity_months ?? 12;
  const selectedTemplate: DocumentTemplate | undefined =
    selected?.kind === "document" ? templates.data?.find((template) => template.id === selected.id) : undefined;
  const loadError = templates.error ?? outstanding.error ?? health.error;
  const loading = (access.documents && templates.isPending) || (access.health && health.isPending);

  return (
    <Shell>
      <BackLink href={adminHref("/admin/users", organizationSlug)}>{t("crumbUsers")}</BackLink>
      <PageHeader
        title={t("title")}
        actions={
          access.manage ? (
            <>
              {settings.data ? (
                <button
                  type="button"
                  onClick={() => setSettingsOpen(true)}
                  className={pageHeaderActionClass}
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
                >
                  {t("settings")}
                </button>
              ) : null}
              <button
                type="button"
                onClick={() => setNewOpen(true)}
                className={pageHeaderActionClass}
                style={{ background: "var(--panel)", border: "1px solid var(--primary)", color: "var(--primary)" }}
              >
                {t("newDocument")}
              </button>
            </>
          ) : null
        }
      />

      {loadError ? <ErrorNotice>{documentError(loadError, t, i18n).message}</ErrorNotice> : null}

      {loading ? (
        <StatusText tone="muted">{t("loading")}</StatusText>
      ) : rows.length === 0 ? (
        <StatusText tone="muted">{t("noDocumentsStaff")}</StatusText>
      ) : (
        <ul className="overflow-hidden rounded-[1.5rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="documents-list">
          {rows.map((row, index) => {
            const key = row.kind === "health" ? "health" : row.template.id;
            const isSelected = selected?.kind === "health" ? row.kind === "health" : selected?.kind === "document" && row.kind === "document" && row.template.id === selected.id;
            const title = row.kind === "health" ? t("healthTitle") : row.template.title;
            const mandatory = row.kind === "health" ? row.required : row.template.requirement === "mandatory";
            const blocks = row.kind === "health" ? row.required && healthBlocks : mandatory && gateOn && Boolean(settings.data);
            const meta =
              row.kind === "health"
                ? [row.required ? t("healthValidity", { count: months }) : t("notAskedFor")]
                : [t("versionNumber", { number: row.template.current_version_number }), mandatory ? t("mandatory") : t("optional")];
            return (
              <li key={key} style={index > 0 ? { borderTop: "1px solid var(--border)" } : undefined}>
                <button
                  type="button"
                  onClick={() => setSelected(row.kind === "health" ? { kind: "health" } : { kind: "document", id: row.template.id })}
                  className="flex w-full items-center gap-4 px-5 py-4 text-left"
                  style={{ background: isSelected ? "color-mix(in srgb, var(--primary) 6%, var(--panel))" : "transparent" }}
                  data-testid={`documents-row-${key}`}
                >
                  <span aria-hidden="true" className="text-xl" style={{ color: "var(--primary)" }}>
                    {iconFor(row)}
                  </span>
                  <span className="flex min-w-0 flex-1 flex-col gap-0.5">
                    <span className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
                      {title}
                    </span>
                    <span className="flex flex-wrap gap-x-3 text-xs" style={{ color: "var(--dim)" }}>
                      {meta.map((part) => (
                        <span key={part}>{part}</span>
                      ))}
                      {blocks ? <span>🔒 {t("blocksBookingShort")}</span> : null}
                    </span>
                  </span>
                  <span className="flex shrink-0 flex-wrap justify-end gap-1.5">
                    {row.kind === "health" && !row.required ? null : row.missing > 0 ? (
                      <Pill tone="danger">{t("missingCount", { count: row.missing })}</Pill>
                    ) : mandatory ? (
                      <Pill tone="success">{t("allOkShort")}</Pill>
                    ) : (
                      <Pill tone="neutral">{t("signedCount", { count: row.kind === "document" ? row.signed : 0 })}</Pill>
                    )}
                    {row.kind === "health" && row.expiring > 0 ? <Pill tone="warning">{t("expiringCount", { count: row.expiring })}</Pill> : null}
                  </span>
                </button>
              </li>
            );
          })}
        </ul>
      )}

      {access.manage ? <Hint>{t("startersLine")}</Hint> : null}
      {access.documents ? null : <Hint>{t("healthOnlyHint")}</Hint>}

      {selectedTemplate ? (
        <DocumentPanel
          key={selectedTemplate.id}
          template={selectedTemplate}
          outstanding={outstanding.data?.find((row) => row.template_id === selectedTemplate.id)}
          settings={settings.data}
          canManage={access.manage}
          onClose={() => setSelected(null)}
          onChanged={() => void invalidate()}
        />
      ) : null}
      {selected?.kind === "health" && health.data ? (
        <HealthPanel health={health.data} settings={settings.data} canManage={access.manage} onClose={() => setSelected(null)} onChanged={() => void invalidate()} />
      ) : null}
      {newOpen ? (
        <NewDocumentDialog
          settings={settings.data}
          onClose={() => setNewOpen(false)}
          onCreated={(id) => {
            setNewOpen(false);
            void invalidate();
            setSelected({ kind: "document", id });
          }}
        />
      ) : null}
      {settingsOpen && settings.data ? (
        <SettingsDialog
          settings={settings.data}
          onClose={() => setSettingsOpen(false)}
          onSaved={() => {
            setSettingsOpen(false);
            void invalidate();
          }}
        />
      ) : null}
    </Shell>
  );
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <main className="min-h-screen px-4 py-8 md:px-10 md:py-12" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-4xl flex-col gap-5">{children}</div>
    </main>
  );
}

/** «Έγγραφα» next to «Πρόσκληση» on Χρήστες, for staff who can open the page. */
export function DocumentsLink() {
  const t = useTranslations("Documents");
  const organizationSlug = useOrganizationSlug();
  return (
    <Link
      href={adminHref("/admin/documents", organizationSlug)}
      className={pageHeaderActionClass}
      style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
      data-testid="users-documents-link"
    >
      {t("title")}
    </Link>
  );
}
