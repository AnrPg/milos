"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useId, useState, type ReactNode } from "react";

import { fetchAdminSettings } from "@/api/settings";
import { fetchSettingsCatalog, type CatalogSetting } from "@/api/setup";
import { useSession } from "@/components/session-provider";
import { FRESHNESS } from "@/lib/query-policy";

// CP-H1 (ADR-255, mockup s10 A): settings whose default suits most boxes live
// under «Προχωρημένα», closed by default. Settings the app or a setup recipe
// works out ("derive") are not inputs, and "remove" ones are not shown at all.
// The levels come from the API: `advanced_settings` on GET /admin/settings and
// the catalog GET /admin/setup/settings.

export const SETTINGS_CATALOG_KEY = ["admin", "setup", "settings"] as const;

export type SettingVerdict = CatalogSetting["verdict"];

export type SettingLevels = {
  /** Shown on the main screen. */
  basic: (key: string) => boolean;
  /** Under «Προχωρημένα», closed by default. */
  advanced: (key: string) => boolean;
  /** Not an input: the app or a recipe sets it, or no owner should see it. */
  hidden: (key: string) => boolean;
  /** How many settings sit under «Προχωρημένα». */
  advancedCount: number;
  ready: boolean;
};

/** Pure: the levels from the catalog and the `advanced_settings` list. */
export function settingLevels(catalog: CatalogSetting[] | undefined, advancedSettings: string[] | undefined): SettingLevels {
  const verdicts = new Map((catalog ?? []).map((setting) => [setting.key, setting.verdict]));
  const advancedList = new Set(advancedSettings ?? []);
  const verdict = (key: string): SettingVerdict | undefined => verdicts.get(key);
  const hidden = (key: string) => verdict(key) === "derive" || verdict(key) === "remove";
  const basic = (key: string) => {
    if (hidden(key) || advancedList.has(key)) return false;
    if (catalog) return verdict(key) === "basic";
    // Before the catalog arrives, the settings response's list alone decides.
    return advancedSettings !== undefined;
  };
  return {
    basic,
    hidden,
    // A setting is advanced unless it is basic (ADR-255 §2); while the levels load, nothing is basic.
    advanced: (key: string) => !hidden(key) && !basic(key),
    advancedCount: (catalog ?? []).filter((setting) => setting.verdict === "advanced").length,
    ready: catalog !== undefined,
  };
}

export function useSettingLevels(): SettingLevels {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const catalog = useQuery({
    queryKey: SETTINGS_CATALOG_KEY,
    queryFn: () => fetchSettingsCatalog(token!),
    enabled: Boolean(token),
    staleTime: FRESHNESS.reference,
  });
  const settings = useQuery({
    queryKey: ["admin", "settings"],
    queryFn: () => fetchAdminSettings(token!),
    enabled: Boolean(token),
  });
  return settingLevels(catalog.data?.settings, settings.data?.advanced_settings ?? catalog.data?.advanced_settings);
}

/**
 * «Προχωρημένα» inside one settings area: closed by default, one tap opens
 * it. `count` says how many settings it holds.
 */
export function AdvancedDisclosure({
  count,
  children,
  testId,
}: {
  count?: number;
  children: ReactNode;
  testId?: string;
}) {
  const t = useTranslations("AdvancedSettings");
  const [open, setOpen] = useState(false);
  const id = useId();
  return (
    <section
      className="rounded-2xl p-4"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
      data-testid={testId}
    >
      <button
        type="button"
        aria-expanded={open}
        aria-controls={id}
        onClick={() => setOpen((value) => !value)}
        className="flex w-full items-center justify-between gap-3 text-start"
      >
        <span className="min-w-0">
          <b className="block text-sm" style={{ color: "var(--text)" }}>{t("title")}</b>
          <span className="block text-xs" style={{ color: "var(--muted)" }}>
            {count ? t("hintCount", { count }) : t("hint")}
          </span>
        </span>
        <span aria-hidden="true" style={{ color: "var(--muted)" }}>{open ? "▴" : "▾"}</span>
      </button>
      {open ? (
        <div id={id} className="mt-4 space-y-4">
          {children}
        </div>
      ) : null}
    </section>
  );
}
