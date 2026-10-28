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
import { coachGroups, coachNames, keysOf, toggleCoach, type CoachGroup } from "@/lib/coach-audience";
import { useMyProviders } from "@/components/providers/use-providers";
import { useSession } from "@/components/session-provider";

/**
 * «Οι coach μου» across providers (board 17 Q5; per coach since ANR's call
 * of 2026-10-21): a provider's coaches always see what you did with them; a
 * coach rung on anything else reaches the coaches the member picked once
 * (every coach by default), and any one entry can be narrowed. With a
 * single coach there is nothing to choose.
 */
export const COACH_RUNGS = ["coach_can_view", "coach_reply_requested"] as const;
const ASKED_KEY = "palee:coach-audience-asked";

export function isCoachRung(rung: string) {
  return (COACH_RUNGS as readonly string[]).includes(rung);
}

export function audienceApplies(kind: string) {
  return (AUDIENCE_KINDS as readonly string[]).includes(kind);
}

/** The default audience; `multiple` once there is more than one coach to tell apart. */
export function useCoachAudience() {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const providers = useMyProviders();
  const any = (providers.data?.providers?.length ?? 0) > 0;
  const query = useQuery({
    queryKey: COACH_AUDIENCE_KEY,
    enabled: Boolean(token) && any,
    queryFn: () => fetchCoachAudience(token!),
    staleTime: 60_000,
  });
  const coaches = (query.data?.providers ?? []).reduce((sum, provider) => sum + (provider.coaches?.length ?? 0), 0);
  return { ...query, multiple: coaches > 1 };
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

/** One provider's coaches as chips (one chip with the provider's name for an independent coach). */
export function CoachChips({
  groups,
  selected,
  onToggle,
  disabled = false,
}: {
  groups: CoachGroup[];
  selected: string[];
  onToggle: (key: string) => void;
  disabled?: boolean;
}) {
  const t = useTranslations("Providers");
  return (
    <div className="flex flex-col gap-2">
      {groups.map((group) => (
        <div key={group.organizationId} role="group" aria-label={group.provider} className="flex flex-col gap-1.5">
          {group.coaches.length > 1 ? (
            <span className="text-xs font-semibold" style={{ color: "var(--dim)" }}>
              {group.provider} · {t(`kind.${group.kind}`)}
            </span>
          ) : null}
          <div className="flex flex-wrap gap-2">
            {group.coaches.map((coach) => {
              const on = selected.includes(coach.key);
              const last = on && selected.length === 1;
              return (
                <button
                  key={coach.key}
                  type="button"
                  aria-pressed={on}
                  disabled={last || disabled}
                  onClick={() => onToggle(coach.key)}
                  className="min-h-10 rounded-full px-4 text-sm font-semibold disabled:cursor-not-allowed"
                  style={{
                    background: on ? "color-mix(in srgb, var(--primary) 16%, var(--panel))" : "var(--panel)",
                    border: `1px solid ${on ? "var(--primary)" : "var(--border)"}`,
                    color: on ? "var(--text)" : "var(--text-soft)",
                  }}
                >
                  {on ? "✓ " : ""}
                  {coach.name}
                  {group.coaches.length === 1 && coach.name !== group.provider ? (
                    <span className="ms-1 text-xs font-normal" style={{ color: "var(--dim)" }}>· {group.provider}</span>
                  ) : null}
                </button>
              );
            })}
          </div>
        </div>
      ))}
    </div>
  );
}

/**
 * The coaches under «Οι coach μου» in the visibility picker; at least one
 * stays on. The entry's own provider is left out (its coaches always see
 * it). `makeDefault` adds «Να ισχύει από εδώ και πέρα» the first time.
 */
export function AudienceChooser({
  audience,
  homeOrganizationId,
  selected,
  onChange,
  makeDefault,
  onMakeDefaultChange,
}: {
  audience: CoachAudience;
  homeOrganizationId?: string | null;
  selected: string[];
  onChange: (keys: string[]) => void;
  makeDefault: boolean | null;
  onMakeDefaultChange: (value: boolean) => void;
}) {
  const t = useTranslations("Providers");
  const home = homeOrganizationId ? audience.providers?.find((provider) => provider.organization_id === homeOrganizationId) : null;
  return (
    <fieldset className="mt-3 flex flex-col gap-2 rounded-2xl p-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
      <legend className="px-1 text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        {makeDefault === null ? t("audience.title") : t("audience.askTitle")}
      </legend>
      <p className="text-xs" style={{ color: "var(--text-soft)" }}>
        {home ? t("audience.homeAlways", { name: home.name }) : t("audience.hint")}
      </p>
      <CoachChips groups={coachGroups(audience, homeOrganizationId)} selected={selected} onToggle={(key) => onChange(toggleCoach(selected, key))} />
      {makeDefault !== null ? (
        <label className="flex items-center gap-2 text-sm" style={{ color: "var(--text)" }}>
          <input type="checkbox" checked={makeDefault} onChange={(event) => onMakeDefaultChange(event.target.checked)} />
          {t("audience.makeDefault")}
        </label>
      ) : null}
    </fieldset>
  );
}

/** «Μόνο Μαρία, Νίκος» on an entry narrowed to some coaches. */
export function EntryAudienceNote({ item }: { item: Pick<JournalFeedItem, "audience" | "journal_visibility" | "organization_id"> }) {
  const t = useTranslations("Providers");
  const { data, multiple } = useCoachAudience();
  const audience: EntryAudience | null | undefined = item.audience;
  if (!multiple || !audience?.custom || !isCoachRung(item.journal_visibility) || !data) return null;
  const shared = keysOf(audience.coaches).filter((key) => !key.startsWith(`${item.organization_id ?? ""}:`) || !item.organization_id);
  const names = coachNames(data, shared);
  if (names.length === 0) return null;
  return (
    <span className="text-[11px] font-semibold" style={{ color: "var(--dim)" }}>
      {t("audience.only", { names: names.join(", ") })}
    </span>
  );
}
