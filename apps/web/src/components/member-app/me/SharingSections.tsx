"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  fetchGamificationPreferences,
  listPRs,
  setPRProfileAudience,
  updateGamificationPreferences,
  type GamificationPreferences,
  type PRRecord,
} from "@/api/gamification";
import {
  ENTRY_DEFAULT_KINDS,
  ENTRY_DEFAULTS_KEY,
  fetchEntryDefaults,
  saveEntryDefault,
  type DefaultKind,
  type DefaultRung,
} from "@/api/journal";
import { Switch } from "@/components/body/BodyPreferenceSettings";
import { LoadingLine } from "@/components/client/ClientPage";
import { useSession } from "@/components/session-provider";

const PREFERENCES_KEY = ["gamification", "preferences"] as const;
const RUNGS: readonly DefaultRung[] = ["private", "coach_can_view"];

function SaveError({ failed }: { failed: boolean }) {
  const t = useTranslations("MemberApp");
  if (!failed) return null;
  return <p className="text-sm font-semibold" style={{ color: "var(--danger)" }}>{t("sharing.saveError")}</p>;
}

/**
 * Κοινότητα (ADR-196): whether my PRs become a celebration card in my clubs
 * (off until I opt in) and whether I appear in challenge rankings (on unless
 * I opt out). The leaderboard and Partners switches sit beside them.
 */
export function CommunityOptIns() {
  const t = useTranslations("MemberApp");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const prefs = useQuery({
    queryKey: PREFERENCES_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchGamificationPreferences(token!),
  });
  const save = useMutation({
    mutationFn: (change: Partial<GamificationPreferences>) => updateGamificationPreferences(token!, change),
    onSuccess: (data) => queryClient.setQueryData(PREFERENCES_KEY, data),
  });

  if (!prefs.data) return prefs.isPending ? <LoadingLine /> : null;

  return (
    <div className="flex flex-col gap-1">
      <Switch
        label={t("sharing.prCelebrations")}
        hint={t("sharing.prCelebrationsHint")}
        checked={prefs.data.pr_celebrations === true}
        disabled={save.isPending}
        onChange={(next) => save.mutate({ pr_celebrations: next })}
      />
      <Switch
        label={t("sharing.challenges")}
        hint={t("sharing.challengesHint")}
        checked={prefs.data.challenge_rankings !== false}
        disabled={save.isPending}
        onChange={(next) => save.mutate({ challenge_rankings: next })}
      />
      <SaveError failed={save.isError} />
    </div>
  );
}

/**
 * Which of my PRs the people who follow me see on my profile (ADR-196). Each
 * starts private; Εγώ › PRs says how many stay hidden and links here.
 */
export function ProfilePrsSetting() {
  const t = useTranslations("MemberApp");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  // Same key as the Pantheon's unfiltered list and Εγώ › PRs.
  const prs = useQuery({ queryKey: ["prs", ""], enabled: Boolean(token), queryFn: () => listPRs(token!) });
  const save = useMutation({
    mutationFn: ({ id, shown }: { id: string; shown: boolean }) =>
      setPRProfileAudience(token!, id, shown ? "followers" : "private"),
    onSuccess: (pr) =>
      queryClient.setQueryData<PRRecord[]>(["prs", ""], (list) =>
        list?.map((entry) => (entry.id === pr.id ? { ...entry, profile_audience: pr.profile_audience } : entry)),
      ),
    onSettled: () => void queryClient.invalidateQueries({ queryKey: ["prs"] }),
  });

  if (!prs.data) return prs.isPending ? <LoadingLine /> : null;
  if (prs.data.length === 0) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("sharing.profilePrsEmpty")}</p>;
  const sorted = [...prs.data].sort((a, b) => a.name.localeCompare(b.name));

  return (
    <div className="flex flex-col gap-1">
      {sorted.map((pr) => (
        <Switch
          key={pr.id}
          label={pr.name}
          hint={`${pr.current_score} ${pr.unit}`}
          checked={pr.profile_audience === "followers"}
          disabled={save.isPending}
          onChange={(shown) => save.mutate({ id: pr.id, shown })}
        />
      ))}
      <SaveError failed={save.isError} />
    </div>
  );
}

/**
 * Προεπιλογή νέων καταχωρήσεων (ADR-139 §3, ADR-196): the rung a new workout,
 * note or check-in starts on. Each entry can still be changed on its own.
 */
export function EntryDefaultsSetting() {
  const t = useTranslations("MemberApp");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const defaults = useQuery({
    queryKey: ENTRY_DEFAULTS_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchEntryDefaults(token!),
  });
  const save = useMutation({
    mutationFn: ({ kind, rung }: { kind: DefaultKind; rung: DefaultRung }) => saveEntryDefault(token!, kind, rung),
    onSuccess: (data) => queryClient.setQueryData(ENTRY_DEFAULTS_KEY, data),
  });

  if (!defaults.data) return defaults.isPending ? <LoadingLine /> : null;
  const current = defaults.data;

  return (
    <div className="flex flex-col gap-1">
      {ENTRY_DEFAULT_KINDS.map((kind) => (
        <label key={kind} className="flex min-h-11 items-center justify-between gap-3">
          <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t(`sharing.defaultKind.${kind}`)}</span>
          <select
            value={current[kind]}
            disabled={save.isPending}
            onChange={(event) => save.mutate({ kind, rung: event.target.value as DefaultRung })}
            className="min-h-11 rounded-xl px-3 text-sm font-semibold"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {RUNGS.map((rung) => (
              <option key={rung} value={rung}>
                {t(`journal.visibility.${rung}`)}
              </option>
            ))}
          </select>
        </label>
      ))}
      <SaveError failed={save.isError} />
    </div>
  );
}
