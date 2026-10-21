"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchAdminSettings, updateAdminSettings, type ProviderKind } from "@/api/settings";
import { MY_PROVIDERS_KEY } from "@/api/providers";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

const KINDS: ProviderKind[] = ["gym", "coach"];

/**
 * How members see this organization (ADR-162): a box, or an independent
 * coach. It names the provider in Box ▾, on every journal label and in
 * «Οι coach μου». Only the owner changes it; admins see it.
 */
export function ProviderKindSetting({ token }: { token: string }) {
  const t = useTranslations("Providers");
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const settings = useQuery({ queryKey: ["admin", "settings"], queryFn: () => fetchAdminSettings(token) });
  const [chosen, setChosen] = useState<ProviderKind | null>(null);
  const provider = settings.data?.provider;
  const kind = chosen ?? provider?.kind ?? "gym";
  const editable = provider?.editable ?? false;

  const save = useMutation({
    mutationFn: (next: ProviderKind) => updateAdminSettings(token, { provider: { kind: next } }),
    onSuccess: (data) => {
      queryClient.setQueryData(["admin", "settings"], data);
      void queryClient.invalidateQueries({ queryKey: MY_PROVIDERS_KEY });
      setChosen(null);
    },
  });

  if (!provider) return null;
  const dirty = kind !== provider.kind;

  return (
    <div className="space-y-4">
      <div role="radiogroup" aria-label={t("kindSetting.title")} className="grid gap-3 md:grid-cols-2">
        {KINDS.map((value) => {
          const selected = kind === value;
          return (
            <button
              key={value}
              type="button"
              role="radio"
              aria-checked={selected}
              disabled={!editable || save.isPending}
              onClick={() => setChosen(value)}
              className="rounded-[1.2rem] border p-4 text-start disabled:cursor-not-allowed"
              style={{
                background: selected ? "color-mix(in srgb, var(--primary) 12%, var(--panel-muted))" : "var(--panel-muted)",
                borderColor: selected ? "var(--primary)" : "var(--border)",
              }}
            >
              <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>{t(`kind.${value}`)}</span>
              <span className="mt-1 block text-xs leading-5" style={{ color: "var(--muted)" }}>
                {t(`kindSetting.${value}`)}
              </span>
            </button>
          );
        })}
      </div>
      {editable ? null : (
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("kindSetting.ownerOnly")}</p>
      )}
      {save.error ? (
        <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{localizeError(save.error, i18n)}</p>
      ) : null}
      {editable && dirty ? (
        <div className="flex gap-2">
          <button
            type="button"
            onClick={() => save.mutate(kind)}
            disabled={save.isPending}
            className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {t("kindSetting.save")}
          </button>
          <button
            type="button"
            onClick={() => setChosen(null)}
            className="rounded-full px-5 py-2 text-sm font-semibold"
            style={{ color: "var(--text-soft)", border: "1px solid var(--border)" }}
          >
            {t("kindSetting.cancel")}
          </button>
        </div>
      ) : null}
    </div>
  );
}
