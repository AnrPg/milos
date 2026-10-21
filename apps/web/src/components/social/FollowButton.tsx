"use client";

import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { FEED_KEY } from "@/api/community";
import { fetchFollowStatus, follow, followKey, SOCIAL_KEY, unfollow, type FollowStatus, type FollowTargetType } from "@/api/social";
import { clientErrorMessage } from "@/components/client/errors";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";

/**
 * Follow a person or a box (plan §5a Q9): «Ακολούθησε» → «Εκκρεμεί» →
 * «Ακολουθείς ✓». A person approves each request; a box is followed at once.
 * Unfollowing, or withdrawing a request, asks first.
 */
export function FollowButton({
  targetType,
  targetId,
  initialStatus,
  followsMe = false,
  wide = false,
}: {
  targetType: FollowTargetType;
  targetId: string;
  initialStatus?: FollowStatus;
  followsMe?: boolean;
  wide?: boolean;
}) {
  const t = useTranslations("Social");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const key = followKey(targetType, targetId);
  const status = useQuery({
    queryKey: key,
    enabled: Boolean(token),
    initialData: initialStatus,
    queryFn: () => fetchFollowStatus(token!, targetType, targetId),
  });
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const current = status.data ?? "none";

  async function run(action: () => Promise<FollowStatus>) {
    if (!token || busy) return;
    setBusy(true);
    setError(null);
    try {
      queryClient.setQueryData(key, await action());
      setConfirming(false);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: SOCIAL_KEY }),
        queryClient.invalidateQueries({ queryKey: FEED_KEY }),
      ]);
    } catch (caught) {
      setError(clientErrorMessage(caught, tUi));
    } finally {
      setBusy(false);
    }
  }

  const base = `min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-50 ${wide ? "w-full" : ""}`;

  if (confirming) {
    return (
      <div className={`flex flex-col gap-2 ${wide ? "w-full" : ""}`}>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>
          {current === "requested" ? t("withdrawConfirm") : targetType === "organization" ? t("unfollowBoxConfirm") : t("unfollowConfirm")}
        </p>
        <div className="flex gap-2">
          <button
            type="button"
            className={`${base} flex-1`}
            style={{ border: "1px solid var(--border)", color: "var(--text)" }}
            onClick={() => setConfirming(false)}
          >
            {t("keep")}
          </button>
          <button
            type="button"
            disabled={busy}
            className={`${base} flex-1`}
            style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}
            onClick={() => void run(() => unfollow(token!, targetType, targetId))}
          >
            {current === "requested" ? t("withdraw") : t("unfollow")}
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className={`flex flex-col gap-1 ${wide ? "w-full" : ""}`}>
      {current === "none" ? (
        <button
          type="button"
          disabled={busy || !token}
          className={base}
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          onClick={() => void run(() => follow(token!, targetType, targetId))}
        >
          {followsMe ? t("followBack") : t("follow")}
        </button>
      ) : (
        <button
          type="button"
          disabled={busy}
          aria-pressed="true"
          className={base}
          style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
          onClick={() => setConfirming(true)}
        >
          {current === "requested" ? t("requested") : (
            <span className="inline-flex items-center gap-1.5">
              {t("following")}
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="M20 6 9 17l-5-5" />
              </svg>
            </span>
          )}
        </button>
      )}
      {error ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{error}</p> : null}
    </div>
  );
}
