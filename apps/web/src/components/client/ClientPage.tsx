"use client";

import Link from "next/link";

import { useUiTranslations } from "@/i18n/ui";
import { PageHeader } from "@/components/PageHeader";
import { isNotEntitledError } from "@/components/client/entitlement";
import { clientErrorMessage } from "@/components/client/errors";

/** Shared frame for client (member/athlete) pages. */
export function ClientPage({
  title,
  actions,
  children,
}: {
  title: string;
  intro?: string;
  actions?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <main className="min-h-screen px-4 py-8 md:px-10 md:py-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-4xl flex-col gap-6">
        <div className="flex flex-wrap items-end justify-between gap-3">
          <PageHeader title={title} />
          {actions}
        </div>
        {children}
      </div>
    </main>
  );
}

export function ClientCard({
  title,
  children,
  aside,
  id,
}: {
  title?: string;
  children: React.ReactNode;
  aside?: React.ReactNode;
  id?: string;
}) {
  return (
    <section
      id={id}
      aria-label={title}
      className="rounded-2xl p-4 sm:p-5"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      {title || aside ? (
        <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
          {title ? (
            <h2 className="text-sm font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
              {title}
            </h2>
          ) : <span />}
          {aside}
        </div>
      ) : null}
      {children}
    </section>
  );
}

/** Friendly state for a service the client's package does not include. */
export function NotIncluded() {
  const i18n = useUiTranslations();
  return (
    <section
      className="rounded-2xl p-6 text-center"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <h2 className="text-lg font-semibold" style={{ color: "var(--text)" }}>
        {i18n("clNotIncludedTitle")}
      </h2>
      <p className="mx-auto mt-2 max-w-md text-sm" style={{ color: "var(--muted)" }}>
        {i18n("clNotIncludedBody")}
      </p>
      <Link
        href="/account/billing"
        className="mt-4 inline-block rounded-full px-4 py-2 text-sm font-semibold"
        style={{ background: "var(--border)", color: "var(--text)" }}
      >
        {i18n("clViewMyPackage")}
      </Link>
    </section>
  );
}

export function LoadingLine() {
  const i18n = useUiTranslations();
  return (
    <p className="text-sm" role="status" style={{ color: "var(--dim)" }}>
      {i18n("loading33ce417")}
    </p>
  );
}

/** Error line for a failed load; a 403 shows the not-included state instead. */
export function QueryProblem({ error, onRetry }: { error: unknown; onRetry?: () => void }) {
  const i18n = useUiTranslations();
  if (isNotEntitledError(error)) return <NotIncluded />;
  return (
    <div role="alert" className="flex flex-wrap items-center gap-3 text-sm" style={{ color: "var(--danger)" }}>
      <span>{clientErrorMessage(error, i18n)}</span>
      {onRetry ? (
        <button
          type="button"
          onClick={onRetry}
          className="rounded-full px-3 py-1 text-xs font-semibold"
          style={{ background: "var(--border)", color: "var(--text)" }}
        >
          {i18n("retry9f5cd8a")}
        </button>
      ) : null}
    </div>
  );
}

export function EmptyLine({ children }: { children: React.ReactNode }) {
  return (
    <p className="rounded-xl px-4 py-4 text-sm" style={{ background: "var(--panel-muted)", color: "var(--dim)" }}>
      {children}
    </p>
  );
}
