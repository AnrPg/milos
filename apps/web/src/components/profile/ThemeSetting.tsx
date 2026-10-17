"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";

import { SESSION_UPDATED_EVENT } from "@/api/client";
import { updateProfile } from "@/api/profile";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";
import { APP_THEMES, THEME_SLUGS, type ThemeSlug } from "@/lib/theme";

/**
 * Ρυθμίσεις › Θέμα: the member's own theme, saved on their account so every
 * device follows it, or their gym's theme (the default).
 */
export function ThemeSetting() {
  const t = useTranslations("Profile");
  const i18n = useUiTranslations();
  const { tokens, currentUser } = useSession();
  const current = (currentUser?.preferred_theme_slug ?? null) as ThemeSlug | null;
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function choose(slug: ThemeSlug | null) {
    if (!tokens || !currentUser || slug === current) return;
    setPending(true);
    setError(null);
    try {
      const result = await updateProfile(tokens.access_token, { preferred_theme_slug: slug });
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

  const option = (slug: ThemeSlug | null) => {
    const selected = slug === current;
    const colors = slug ? APP_THEMES[slug].colors : null;
    return (
      <button
        key={slug ?? "gym"}
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
        {colors ? (
          <span className="mb-2 flex gap-1.5" aria-hidden="true">
            {[colors.background, colors.primary, colors.success].map((color) => (
              <span key={color} className="h-4 w-4 rounded-full" style={{ background: color, border: "1px solid var(--border)" }} />
            ))}
          </span>
        ) : null}
        <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>
          {slug ? i18n(APP_THEMES[slug].label) : t("themeGym")}
        </span>
        {slug ? null : (
          <span className="mt-1 block text-xs" style={{ color: "var(--muted)" }}>{t("themeGymHint")}</span>
        )}
      </button>
    );
  };

  return (
    <div className="space-y-3">
      <div role="radiogroup" aria-label={t("themeTitle")} className="grid grid-cols-2 gap-2 sm:grid-cols-3">
        {option(null)}
        {THEME_SLUGS.map((slug) => option(slug))}
      </div>
      {error ? <p role="alert" className="text-sm font-semibold" style={{ color: "var(--danger)" }}>{error}</p> : null}
    </div>
  );
}
