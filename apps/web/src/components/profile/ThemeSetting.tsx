"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";

import { SESSION_UPDATED_EVENT } from "@/api/client";
import { updateProfile } from "@/api/profile";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";
import { APP_THEMES, DEFAULT_THEME_SLUG, THEME_SLUGS, normalizeThemeSlug, type ThemeSlug } from "@/lib/theme";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/**
 * Ρυθμίσεις › Θέμα: light (Frost, the default) or dark (Graphite), saved on
 * the member's account so every device follows it. The palette is the same
 * Palee one for everyone.
 */
export function ThemeSetting() {
  const t = useTranslations("Profile");
  const i18n = useUiTranslations();
  const { tokens, currentUser } = useSession();
  const current = normalizeThemeSlug(currentUser?.preferred_theme_slug);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function choose(slug: ThemeSlug) {
    if (!tokens || !currentUser || slug === current) return;
    setPending(true);
    setError(null);
    try {
      const result = await updateProfile(tokens.access_token, { preferred_theme_slug: slug === DEFAULT_THEME_SLUG ? null : slug });
      window.dispatchEvent(
        new CustomEvent(SESSION_UPDATED_EVENT, {
          detail: { tokens, currentUser: { ...currentUser, preferred_theme_slug: result.user.preferred_theme_slug ?? null } },
        }),
      );
    } catch {
      setError(t("themeError"));
    } finally {
      setPending(false);
    }
  }

  const option = (slug: ThemeSlug) => {
    const selected = slug === current;
    const { tokens: colors } = APP_THEMES[slug];
    return (
      <button
        key={slug}
        type="button"
        role="radio"
        aria-checked={selected}
        disabled={pending}
        onClick={() => void choose(slug)}
        className="min-h-11 rounded-[1.2rem] border p-3 text-start disabled:opacity-60"
        style={{
          background: selected ? "color-mix(in srgb, var(--primary) 12%, var(--panel-muted))" : "var(--panel-muted)",
          borderColor: selected ? "var(--primary)" : "var(--border)",
        }}
      >
        <span className="mb-2 flex gap-1.5" aria-hidden="true">
          {[colors.bg, colors.primary, colors.spark].map((color) => (
            <span key={color} className="h-4 w-4 rounded-full" style={{ background: color, border: "1px solid var(--border)" }} />
          ))}
        </span>
        <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>
          {i18n(APP_THEMES[slug].label)}
        </span>
        <span className="mt-1 block text-xs" style={{ color: "var(--muted)" }}>{i18n(APP_THEMES[slug].description)}</span>
      </button>
    );
  };

  return (
    <div className="space-y-3">
      <div role="radiogroup" aria-label={t("themeTitle")} className="grid grid-cols-2 gap-2">
        {THEME_SLUGS.map((slug) => option(slug))}
      </div>
      {error ? <ErrorNotice>{error}</ErrorNotice> : null}
    </div>
  );
}
