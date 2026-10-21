"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import { Icon } from "./Icon";

/**
 * A tab that needs an account (board 4 D2), logged out: a blurred outline of
 * what is behind it with an inline sign-in card on top (board 5 Q2).
 */
export function LockedTab({ slug, tab }: { slug: string; tab: "schedule" | "events" | "posts" }) {
  const t = useTranslations("BoxPage");
  const next = encodeURIComponent(`/b/${slug}#${tab}`);

  return (
    <div className="relative">
      <div aria-hidden="true" className="flex select-none flex-col gap-2 blur-[3px]" style={{ opacity: 0.6 }}>
        {[0, 1, 2, 3].map((row) => (
          <div key={row} className="grid min-h-16 grid-cols-[3rem_1fr_4rem] items-center gap-3 rounded-2xl px-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <span className="h-3 rounded" style={{ background: "var(--panel-raised)" }} />
            <span className="flex flex-col gap-1.5">
              <span className="h-3 w-2/3 rounded" style={{ background: "var(--panel-raised)" }} />
              <span className="h-2.5 w-1/3 rounded" style={{ background: "var(--panel-raised)" }} />
            </span>
            <span className="h-3 rounded" style={{ background: "var(--panel-raised)" }} />
          </div>
        ))}
      </div>
      <div className="absolute inset-x-0 top-6 flex justify-center px-2">
        <div className="flex w-full max-w-sm flex-col items-center gap-3 rounded-3xl p-5 text-center shadow-[var(--shadow-md)]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <span className="grid h-11 w-11 place-items-center rounded-full" style={{ background: "var(--panel-raised)", color: "var(--text-soft)" }}>
            <Icon name="lock" />
          </span>
          <p className="font-bold" style={{ color: "var(--text)" }}>{t(`locked.${tab}`)}</p>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("lockedHint")}</p>
          <div className="flex w-full flex-col gap-2">
            <Link href={`/register?next=${next}`} className="flex min-h-11 items-center justify-center rounded-2xl text-sm font-bold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
              {t("createAccount")}
            </Link>
            <Link href={`/login?next=${next}`} className="flex min-h-11 items-center justify-center rounded-2xl text-sm font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
              {t("signIn")}
            </Link>
          </div>
        </div>
      </div>
    </div>
  );
}
