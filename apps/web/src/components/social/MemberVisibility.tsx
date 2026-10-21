"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { setMemberVisibility } from "@/api/community";
import { SUMMARY_KEY, type SocialSummary } from "@/api/social";
import { clientErrorMessage } from "@/components/client/errors";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";

import { useSocialSummary } from "./use-social";

/**
 * Κοινοποίηση & ορατότητα › «Μέλη» (board 7 Q1 extra): stay off the members
 * list of your clubs. Coaches and staff still see you where they need to.
 */
export function MemberVisibilitySetting() {
  const t = useTranslations("Clubs");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const summary = useSocialSummary();
  const hidden = summary.data?.member_visibility?.hidden ?? false;
  const save = useMutation({
    mutationFn: (next: boolean) => setMemberVisibility(tokens!.access_token, next),
    onSuccess: (result) =>
      queryClient.setQueryData<SocialSummary>(SUMMARY_KEY, (current) =>
        current ? { ...current, member_visibility: result } : current,
      ),
  });
  if (summary.isPending) return <p style={{ color: "var(--dim)" }}>{t("loading")}</p>;

  return (
    <div className="space-y-4">
      <p className="text-sm" style={{ color: "var(--muted)" }}>{hidden ? t("visibilityHidden") : t("visibilityShown")}</p>
      <button
        type="button"
        aria-pressed={hidden}
        disabled={save.isPending || !summary.data}
        onClick={() => save.mutate(!hidden)}
        className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
        style={{ border: "1px solid var(--border)", color: "var(--text)" }}
      >
        {hidden ? t("visibilityShow") : t("visibilityHide")}
      </button>
      {save.error ? (
        <p role="alert" className="text-sm" style={{ color: "var(--danger, #dc2626)" }}>{clientErrorMessage(save.error, tUi)}</p>
      ) : null}
    </div>
  );
}
