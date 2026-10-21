"use client";

import { useId, useState } from "react";
import Link from "next/link";
import { useTranslations } from "next-intl";

import type { FormerProvider, Provider } from "@/api/providers";
import { clientErrorMessage } from "@/components/client/errors";
import { ErrorLine, Sheet } from "@/components/community/Sheet";
import { ProviderAvatar } from "@/components/providers/SourceLabel";
import { useAdoptAccountProvider, useMyProviders, useSwitchProvider } from "@/components/providers/use-providers";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";
import { paletteColor, providerColor } from "@/lib/provider-sources";

/**
 * Box's title (board 17 Q1): «Box Κυψέλη ▾» opens the sheet of everyone who
 * trains you; with one provider it is plain text.
 */
export function ProviderTitle({ title }: { title: string }) {
  const t = useTranslations("Providers");
  const providers = useMyProviders();
  const [open, setOpen] = useState(false);
  useAdoptAccountProvider();
  const switchable = (providers.data?.providers?.length ?? 0) > 1;

  if (!switchable) return <>{title}</>;
  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-haspopup="dialog"
        aria-label={t("switchLabel", { name: title })}
        className="flex min-w-0 items-center gap-2 text-start"
      >
        <span className="truncate">{title}</span>
        <span aria-hidden="true" className="text-xl" style={{ color: "var(--dim)" }}>▾</span>
      </button>
      {open ? <ProviderSheet onClose={() => setOpen(false)} /> : null}
    </>
  );
}

export function ProviderSheet({ onClose }: { onClose: () => void }) {
  const t = useTranslations("Providers");
  const i18n = useUiTranslations();
  const labelId = useId();
  const providers = useMyProviders();
  const { switchTo, pending, error } = useSwitchProvider();
  const [showFormer, setShowFormer] = useState(false);
  const active = providers.data?.providers ?? [];
  const former = providers.data?.former ?? [];

  async function choose(provider: Provider) {
    if (provider.selected) return onClose();
    if (await switchTo(provider)) onClose();
  }

  return (
    <Sheet title={t("sheetTitle")} onClose={onClose} labelId={labelId}>
      <ul className="flex flex-col">
        {active.map((provider) => (
          <li key={provider.organization_id} style={{ borderBottom: "1px solid var(--border)" }}>
            <button
              type="button"
              onClick={() => void choose(provider)}
              disabled={pending !== null}
              aria-current={provider.selected ? "true" : undefined}
              className="flex min-h-16 w-full items-center gap-3 py-3 text-start disabled:opacity-60"
            >
              <ProviderAvatar name={provider.name} logoUrl={provider.logo_url} color={providerColor(provider)} />
              <span className="min-w-0 flex-1">
                <span className="block truncate font-bold" style={{ color: "var(--text)" }}>{provider.name}</span>
                <ProviderLine provider={provider} />
              </span>
              {pending === provider.organization_id ? (
                <span className="text-xs" style={{ color: "var(--dim)" }}>{t("switching")}</span>
              ) : provider.selected ? (
                <span aria-label={t("current")} style={{ color: "var(--primary-strong)" }}>✓</span>
              ) : null}
            </button>
          </li>
        ))}
      </ul>

      <ErrorLine message={error ? clientErrorMessage(error, i18n) : null} />

      <Link
        href="/me/clubs#join"
        onClick={onClose}
        className="mt-4 flex min-h-11 items-center justify-center gap-2 rounded-2xl px-4 text-sm font-bold"
        style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
      >
        <span aria-hidden="true">＋</span>
        {t("add")}
      </Link>

      {former.length > 0 ? (
        <section className="mt-5">
          <button
            type="button"
            aria-expanded={showFormer}
            onClick={() => setShowFormer((value) => !value)}
            className="flex w-full items-center justify-between text-xs font-bold uppercase tracking-[0.18em]"
            style={{ color: "var(--dim)" }}
          >
            {t("formerTitle", { count: former.length })}
            <span aria-hidden="true">{showFormer ? "▴" : "▾"}</span>
          </button>
          {showFormer ? (
            <>
              <p className="mt-2 text-sm" style={{ color: "var(--text-soft)" }}>{t("formerHint")}</p>
              <ul className="mt-2 flex flex-col gap-3">
                {former.map((provider) => (
                  <FormerRow key={provider.organization_id} provider={provider} />
                ))}
              </ul>
            </>
          ) : null}
        </section>
      ) : null}
    </Sheet>
  );
}

/** «Box · CrossFit 18:00 σήμερα · 1 μήνυμα». */
function ProviderLine({ provider }: { provider: Provider }) {
  const t = useTranslations("Providers");
  const locale = useUiLocale();
  const parts = [t(`kind.${provider.kind}`)];
  if (provider.next) {
    const at = new Date(provider.next.at);
    const today = new Date();
    const time = at.toLocaleTimeString(locale, { hour: "2-digit", minute: "2-digit" });
    const when =
      at.toDateString() === today.toDateString()
        ? t("nextToday", { time })
        : t("nextOn", { day: at.toLocaleDateString(locale, { weekday: "long" }), time });
    parts.push(provider.next.title ? `${provider.next.title} ${when}` : when);
  }
  if (provider.unread_messages > 0) parts.push(t("unread", { count: provider.unread_messages }));
  return (
    <span className="block truncate text-sm" style={{ color: "var(--dim)" }}>
      {parts.join(" · ")}
    </span>
  );
}

function FormerRow({ provider }: { provider: FormerProvider }) {
  const t = useTranslations("Providers");
  const locale = useUiLocale();
  return (
    <li className="flex items-center gap-3">
      <ProviderAvatar name={provider.name} logoUrl={provider.logo_url} color={paletteColor(provider.organization_id)} size={32} />
      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{provider.name}</span>
        <span className="block text-xs" style={{ color: "var(--dim)" }}>
          {provider.ended_at
            ? t("formerSince", { date: new Date(provider.ended_at).toLocaleDateString(locale, { day: "numeric", month: "short", year: "numeric" }) })
            : t(`kind.${provider.kind}`)}
        </span>
      </span>
    </li>
  );
}
