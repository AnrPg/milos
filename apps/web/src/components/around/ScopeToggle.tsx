"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import type { HomeScope } from "./around";
import { useHomeScope } from "./use-around";

/**
 * Αρχική's scope (vision §7.1, mockup `scope`): «Τα clubs μου | Γύρω μου».
 * Each side is a link (Γύρω μου is the deep-linkable /around); the choice is
 * remembered so Αρχική opens where the person left it.
 */
export function ScopeToggle({ current }: { current: HomeScope }) {
  const t = useTranslations("Around");
  const { setScope } = useHomeScope();
  const item = (scope: HomeScope, href: string, label: string) => {
    const on = scope === current;
    return (
      <Link
        href={href}
        replace
        aria-current={on ? "page" : undefined}
        onClick={() => setScope(scope)}
        className="flex min-h-10 flex-1 items-center justify-center rounded-full px-3 text-sm font-bold"
        style={{
          background: on ? "var(--panel-raised)" : "transparent",
          color: on ? "var(--text)" : "var(--dim)",
          boxShadow: on ? "var(--shadow-sm)" : undefined,
        }}
      >
        {label}
      </Link>
    );
  };
  return (
    <nav
      data-tabs
      aria-label={t("scopeLabel")}
      className="flex gap-1 rounded-full p-1"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      {item("clubs", "/", t("scopeClubs"))}
      {item("around", "/around", t("scopeAround"))}
    </nav>
  );
}
