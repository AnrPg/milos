"use client";

import { useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { searchUsers } from "@/api/messaging";
import {
  fetchPRSharing,
  grantPRAccess,
  revokePRAccess,
  updatePRCoachVisibility,
  type PRSharingSettings as PRSharingSettingsData,
} from "@/api/pr-sharing";
import { useSession } from "@/components/session-provider";
import { useUiLocale } from "@/i18n/use-ui-locale";

type Candidate = { id: string; nickname: string };

export const PR_SHARING_QUERY_KEY = ["pr-sharing"] as const;

/**
 * ADR-119: the owner's PR sharing settings - the coach-visibility opt-out
 * (all gyms) and explicit read-only grants to chosen accounts.
 */
export function PRSharingSettings() {
  const t = useTranslations("PrSharing");
  const uiLocale = useUiLocale();
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();

  const [query, setQuery] = useState("");
  const [candidates, setCandidates] = useState<Candidate[]>([]);
  const [searched, setSearched] = useState(false);
  const searchTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const sharingQuery = useQuery({
    queryKey: PR_SHARING_QUERY_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchPRSharing(token!),
  });

  const visibilityMutation = useMutation({
    mutationFn: (enabled: boolean) => updatePRCoachVisibility(token!, enabled),
    onSuccess: (data) => queryClient.setQueryData<PRSharingSettingsData>(PR_SHARING_QUERY_KEY, data),
  });

  const grantMutation = useMutation({
    mutationFn: (granteeUserId: string) => grantPRAccess(token!, granteeUserId),
    onSuccess: () => {
      setQuery("");
      setCandidates([]);
      setSearched(false);
      void queryClient.invalidateQueries({ queryKey: PR_SHARING_QUERY_KEY });
    },
  });

  const revokeMutation = useMutation({
    mutationFn: (grantId: string) => revokePRAccess(token!, grantId),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: PR_SHARING_QUERY_KEY }),
  });

  const sharing = sharingQuery.data;
  const grantedIds = new Set(sharing?.grants.map((grant) => grant.grantee.id) ?? []);
  if (currentUser?.id) grantedIds.add(currentUser.id);

  function handleQueryChange(value: string) {
    setQuery(value);
    if (searchTimer.current) clearTimeout(searchTimer.current);
    if (!value.trim() || !token) {
      setCandidates([]);
      setSearched(false);
      return;
    }
    searchTimer.current = setTimeout(async () => {
      try {
        const data = await searchUsers(token, value);
        setCandidates(data.users.map((user) => ({ id: user.id, nickname: user.nickname })));
      } catch {
        setCandidates([]);
      } finally {
        setSearched(true);
      }
    }, 280);
  }

  if (sharingQuery.isError) {
    return <p className="text-sm font-semibold" style={{ color: "var(--danger)" }}>{t("loadError")}</p>;
  }

  if (!sharing) return null;

  const saveFailed = visibilityMutation.isError || grantMutation.isError || revokeMutation.isError;
  const visibleCandidates = candidates.filter((candidate) => !grantedIds.has(candidate.id));

  return (
    <div className="space-y-6">
      <label className="flex cursor-pointer items-start gap-3">
        <input
          type="checkbox"
          className="mt-1"
          checked={sharing.coach_visibility}
          disabled={visibilityMutation.isPending}
          onChange={(event) => visibilityMutation.mutate(event.target.checked)}
        />
        <span>
          <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>
            {t("coachVisibilityLabel")}
          </span>
          <span className="mt-1 block text-xs" style={{ color: "var(--muted)" }}>
            {t("coachVisibilityHint")}
          </span>
        </span>
      </label>

      <div className="space-y-3">
        <div>
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("grantsTitle")}</p>
          <p className="mt-1 text-xs" style={{ color: "var(--muted)" }}>{t("grantsHint")}</p>
        </div>

        {sharing.grants.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{t("grantsEmpty")}</p>
        ) : (
          <ul className="space-y-2">
            {sharing.grants.map((grant) => (
              <li
                key={grant.id}
                className="flex items-center justify-between gap-3 rounded-xl px-4 py-3"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
              >
                <span>
                  <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>
                    {grant.grantee.display_nickname}
                  </span>
                  <span className="block text-xs" style={{ color: "var(--muted)" }}>
                    {t("sharedSince", { date: new Date(grant.created_at).toLocaleDateString(uiLocale) })}
                  </span>
                </span>
                <button
                  type="button"
                  disabled={revokeMutation.isPending}
                  onClick={() => revokeMutation.mutate(grant.id)}
                  className="rounded-xl px-3 py-2 text-xs font-semibold disabled:opacity-50"
                  style={{ background: "var(--border)", color: "var(--text-soft)" }}
                >
                  {t("revoke")}
                </button>
              </li>
            ))}
          </ul>
        )}

        <div className="space-y-2">
          <label className="block text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--muted)" }}>
            {t("searchLabel")}
            <input
              className="mt-1.5 w-full rounded-xl px-4 py-2.5 text-sm normal-case tracking-normal outline-none"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
              placeholder={t("searchPlaceholder")}
              value={query}
              onChange={(event) => handleQueryChange(event.target.value)}
            />
          </label>
          {searched && visibleCandidates.length === 0 ? (
            <p className="text-xs" style={{ color: "var(--dim)" }}>{t("searchEmpty")}</p>
          ) : null}
          {visibleCandidates.length > 0 ? (
            <ul className="space-y-1">
              {visibleCandidates.map((candidate) => (
                <li key={candidate.id} className="flex items-center justify-between gap-3 rounded-xl px-4 py-2" style={{ border: "1px solid var(--border)" }}>
                  <span className="text-sm" style={{ color: "var(--text)" }}>{candidate.nickname}</span>
                  <button
                    type="button"
                    disabled={grantMutation.isPending}
                    onClick={() => grantMutation.mutate(candidate.id)}
                    className="rounded-xl px-3 py-1.5 text-xs font-semibold disabled:opacity-50"
                    style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                  >
                    {t("share")}
                  </button>
                </li>
              ))}
            </ul>
          ) : null}
        </div>
      </div>

      {saveFailed ? (
        <p className="text-sm font-semibold" style={{ color: "var(--danger)" }}>{t("saveError")}</p>
      ) : null}
    </div>
  );
}
