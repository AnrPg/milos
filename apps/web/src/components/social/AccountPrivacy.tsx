"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { setSocialPrivacy, SOCIAL_KEY, SUMMARY_KEY, type SocialPrivacyRequest, type SocialSummary } from "@/api/social";
import { clientErrorMessage } from "@/components/client/errors";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";

import { useSocialSummary } from "./use-social";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/**
 * Κοινοποίηση & ορατότητα › «Ιδιωτικός λογαριασμός» and «Εμφάνιση στην
 * αναζήτηση» (ADR-193 §2). Private is the default: every follow is a request.
 * Going public accepts the requests that are waiting, so with any waiting it
 * asks first; going private again keeps current followers.
 */
export function AccountPrivacySetting() {
  const t = useTranslations("Social");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const summary = useSocialSummary();
  const privacy = summary.data?.privacy;
  const privateAccount = privacy?.private_account ?? true;
  const searchable = privacy?.searchable ?? true;
  const waiting = summary.data?.requests_count ?? 0;
  const [confirmingPublic, setConfirmingPublic] = useState(false);

  const save = useMutation({
    mutationFn: (body: SocialPrivacyRequest) => setSocialPrivacy(tokens!.access_token, body),
    onSuccess: async (result, body) => {
      setConfirmingPublic(false);
      queryClient.setQueryData<SocialSummary>(SUMMARY_KEY, (current) => (current ? { ...current, privacy: result } : current));
      // Going public accepted the waiting requests: counts and lists move.
      if (body.private_account === false) await queryClient.invalidateQueries({ queryKey: SOCIAL_KEY });
    },
  });

  if (summary.isPending) return <p style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  const disabled = save.isPending || !summary.data;

  function togglePrivate() {
    if (privateAccount && waiting > 0) {
      setConfirmingPublic(true);
      return;
    }
    save.mutate({ private_account: !privateAccount });
  }

  return (
    <div className="space-y-5">
      <div className="space-y-2">
        <Switch
          id="private-account"
          label={t("privateAccountToggle")}
          checked={privateAccount}
          disabled={disabled || confirmingPublic}
          onToggle={togglePrivate}
        />
        <p id="private-account-state" className="text-sm" style={{ color: "var(--muted)" }}>
          {privateAccount ? t("privateAccountOn") : t("privateAccountOff")}
        </p>
        {confirmingPublic ? (
          <div className="space-y-3 rounded-2xl p-4" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}>
            <p className="text-sm" style={{ color: "var(--text)" }}>{t("goPublicConfirm", { count: waiting })}</p>
            <div className="flex flex-wrap gap-2">
              <button
                type="button"
                onClick={() => setConfirmingPublic(false)}
                className="min-h-11 flex-1 rounded-2xl px-4 text-sm font-semibold"
                style={{ border: "1px solid var(--border)", color: "var(--text)" }}
              >
                {t("keepPrivate")}
              </button>
              <button
                type="button"
                disabled={save.isPending}
                onClick={() => save.mutate({ private_account: false })}
                className="min-h-11 flex-1 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              >
                {t("goPublic")}
              </button>
            </div>
          </div>
        ) : null}
      </div>
      <div className="space-y-2">
        <Switch
          id="searchable"
          label={t("searchableToggle")}
          checked={searchable}
          disabled={disabled}
          onToggle={() => save.mutate({ searchable: !searchable })}
        />
        <p id="searchable-state" className="text-sm" style={{ color: "var(--muted)" }}>
          {/* A private account shows up only to people who already know it (ADR-193 §4). */}
          {!searchable ? t("searchableOff") : privateAccount ? t("searchablePrivate") : t("searchableOn")}
        </p>
      </div>
      {save.error ? (
        <ErrorNotice>{clientErrorMessage(save.error, tUi)}</ErrorNotice>
      ) : null}
    </div>
  );
}

/** The switch used across Κοινοποίηση & ορατότητα (see «Φαίνομαι στο Γύρω μου»). */
function Switch({
  id,
  label,
  checked,
  disabled,
  onToggle,
}: {
  id: string;
  label: string;
  checked: boolean;
  disabled: boolean;
  onToggle: () => void;
}) {
  return (
    <div className="flex items-center justify-between gap-4">
      <span id={`${id}-label`} className="text-sm font-semibold" style={{ color: "var(--text)" }}>
        {label}
      </span>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-labelledby={`${id}-label`}
        aria-describedby={`${id}-state`}
        disabled={disabled}
        onClick={onToggle}
        className="relative h-8 w-14 shrink-0 rounded-full disabled:opacity-60"
        style={{ background: checked ? "var(--primary)" : "var(--panel-raised)", border: "1px solid var(--border)" }}
      >
        <span
          aria-hidden="true"
          className="absolute top-1 h-5 w-5 rounded-full transition-all"
          style={{ insetInlineStart: checked ? "1.9rem" : "0.25rem", background: checked ? "var(--bg)" : "var(--text)" }}
        />
      </button>
    </div>
  );
}
