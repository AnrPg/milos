"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  AUDIENCE_KINDS,
  COACH_AUDIENCE_KEY,
  fetchCoachAudience,
  type CoachAudience,
  type EntryAudience,
  type JournalFeedItem,
} from "@/api/journal";
import { useMyProviders } from "@/components/providers/use-providers";
import { useSession } from "@/components/session-provider";

/**
 * «Οι coach μου» across providers (board 17 Q5): a provider always sees what
 * you did with them; a coach rung reaches the coaches of the providers the
 * member picked once (all active ones by default), and any one entry can be
 * narrowed. With a single provider there is nothing to choose.
 */
export const COACH_RUNGS = ["coach_can_view", "coach_reply_requested"] as const;
const ASKED_KEY = "milos:coach-audience-asked";

export function isCoachRung(rung: string) {
  return (COACH_RUNGS as readonly string[]).includes(rung);
}

export function audienceApplies(kind: string) {
  return (AUDIENCE_KINDS as readonly string[]).includes(kind);
}

/** The default audience, read only when there is more than one provider. */
export function useCoachAudience() {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const providers = useMyProviders();
  const multiple = (providers.data?.providers?.length ?? 0) > 1;
  const query = useQuery({
    queryKey: [...COACH_AUDIENCE_KEY, token],
    enabled: Boolean(token) && multiple,
    queryFn: () => fetchCoachAudience(token!),
    staleTime: 60_000,
  });
  return { ...query, multiple };
}

/** Whether this device already asked who «Οι coach μου» means. */
export function audienceAsked() {
  try {
    return window.localStorage.getItem(ASKED_KEY) === "1";
  } catch {
    return true;
  }
}

export function markAudienceAsked() {
  try {
    window.localStorage.setItem(ASKED_KEY, "1");
  } catch {}
}

/**
 * The providers' chips under «Οι coach μου» in the visibility picker; at
 * least one stays on. `askDefault` adds «Κάνε το προεπιλογή», on the first
 * time it is asked.
 */
export function AudienceChooser({
  audience,
  selected,
  onChange,
  makeDefault,
  onMakeDefaultChange,
}: {
  audience: CoachAudience;
  selected: string[];
  onChange: (ids: string[]) => void;
  makeDefault: boolean | null;
  onMakeDefaultChange: (value: boolean) => void;
}) {
  const t = useTranslations("Providers");
  return (
    <fieldset className="mt-3 flex flex-col gap-2 rounded-2xl p-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
      <legend className="px-1 text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        {makeDefault === null ? t("audience.title") : t("audience.askTitle")}
      </legend>
      <p className="text-xs" style={{ color: "var(--text-soft)" }}>{t("audience.hint")}</p>
      <div className="flex flex-wrap gap-2">
        {audience.providers.map((provider) => {
          const on = selected.includes(provider.organization_id);
          const last = on && selected.length === 1;
          return (
            <button
              key={provider.organization_id}
              type="button"
              aria-pressed={on}
              disabled={last}
              onClick={() =>
                onChange(on ? selected.filter((id) => id !== provider.organization_id) : [...selected, provider.organization_id])
              }
              className="min-h-10 rounded-full px-4 text-sm font-semibold disabled:cursor-not-allowed"
              style={{
                background: on ? "color-mix(in srgb, var(--primary) 16%, var(--panel))" : "var(--panel)",
                border: `1px solid ${on ? "var(--primary)" : "var(--border)"}`,
                color: on ? "var(--text)" : "var(--text-soft)",
              }}
            >
              {on ? "✓ " : ""}
              {provider.name}
              <span className="ms-1 text-xs font-normal" style={{ color: "var(--dim)" }}>· {t(`kind.${provider.kind}`)}</span>
            </button>
          );
        })}
      </div>
      {makeDefault !== null ? (
        <label className="flex items-center gap-2 text-sm" style={{ color: "var(--text)" }}>
          <input type="checkbox" checked={makeDefault} onChange={(event) => onMakeDefaultChange(event.target.checked)} />
          {t("audience.makeDefault")}
        </label>
      ) : null}
    </fieldset>
  );
}

/** «→ Νίκος Π.» on an entry narrowed to some providers. */
export function EntryAudienceNote({ item }: { item: Pick<JournalFeedItem, "audience" | "journal_visibility"> }) {
  const t = useTranslations("Providers");
  const { data, multiple } = useCoachAudience();
  const audience: EntryAudience | null | undefined = item.audience;
  if (!multiple || !audience?.custom || !isCoachRung(item.journal_visibility) || !data) return null;
  const names = (data.providers ?? [])
    .filter((provider) => audience.organization_ids.includes(provider.organization_id))
    .map((provider) => provider.name);
  if (names.length === 0) return null;
  return (
    <span className="text-[11px] font-semibold" style={{ color: "var(--dim)" }}>
      {t("audience.only", { names: names.join(", ") })}
    </span>
  );
}

export function sameIds(a: string[], b: string[]) {
  return a.length === b.length && a.every((id) => b.includes(id));
}
