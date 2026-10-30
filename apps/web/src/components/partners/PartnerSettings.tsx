"use client";

import Link from "next/link";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useFormatter, useTranslations } from "next-intl";

import { BLOCKS_KEY, PARTNERS_KEY, PARTNER_SETTINGS_KEY, putPartnerSettings, unblockPerson } from "@/api/partners";
import { SwitchRow } from "@/components/buddy/BuddyBits";
import { ErrorLine } from "@/components/community/Sheet";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useUiTranslations } from "@/i18n/ui";

import { partnerErrorMessage } from "./errors";
import { PARTNERS_HREF } from "./partners-model";
import { useBlocks, usePartnerSettings, usePartnersToken } from "./use-partners";

/**
 * Κοινοποίηση & ορατότητα › Συναθλητές (ADR-280): one switch takes me out of
 * the public deck or brings me back; my profile and matches stay. Nothing to
 * switch until I have a profile, which starts from Γύρω μου.
 */
export function PartnerVisibilitySetting() {
  const t = useTranslations("Partners");
  const tUi = useUiTranslations();
  const token = usePartnersToken();
  const queryClient = useQueryClient();
  const settings = usePartnerSettings();
  const save = useMutation({
    mutationFn: (visible: boolean) => putPartnerSettings(token!, visible),
    onSuccess: (data) => {
      queryClient.setQueryData(PARTNER_SETTINGS_KEY, data);
      void queryClient.invalidateQueries({ queryKey: PARTNERS_KEY });
    },
  });
  if (!settings.data) return null;
  const visible = save.isPending && save.variables !== undefined ? save.variables : Boolean(settings.data.visible);
  return (
    <div className="flex flex-col gap-2" data-testid="partner-visibility">
      {!settings.data.has_profile ? (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>
          {t("settingsNone")}{" "}
          <Link href={PARTNERS_HREF} className="font-semibold underline" style={{ color: "var(--primary)" }}>
            {t("settingsStart")}
          </Link>
        </p>
      ) : (
        <SwitchRow
          checked={visible}
          disabled={save.isPending}
          onChange={(next) => save.mutate(next)}
          label={t("settingsSwitch")}
          hint={t("settingsSwitchHint")}
        />
      )}
      <ErrorLine message={partnerErrorMessage(save.error, t, tUi)} />
    </div>
  );
}

/** People you blocked (ADR-169 §5, ADR-280), across the app; unblocking doesn't bring back what ended. */
export function BlockedPeople() {
  const t = useTranslations("Partners");
  const tUi = useUiTranslations();
  const format = useFormatter();
  const token = usePartnersToken();
  const queryClient = useQueryClient();
  const blocks = useBlocks();
  const unblock = useMutation({
    mutationFn: (userId: string) => unblockPerson(token!, userId),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: BLOCKS_KEY });
      void queryClient.invalidateQueries({ queryKey: PARTNERS_KEY });
    },
  });
  const rows = blocks.data ?? [];
  return (
    <div className="flex flex-col gap-2" data-testid="blocked-people">
      {rows.length === 0 ? (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("blockedEmpty")}</p>
      ) : (
        <ul className="flex flex-col gap-2">
          {rows.map((row) => {
            const name = row.person.nickname ?? t("someone");
            return (
              <li key={row.person.id} className="flex min-h-12 items-center justify-between gap-3">
                <span className="flex min-w-0 items-center gap-3">
                  <PersonAvatar name={name} url={row.person.avatar_url} size={32} />
                  <span className="min-w-0">
                    <span className="block truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{name}</span>
                    <span className="block text-xs" style={{ color: "var(--dim)" }}>
                      {t("blockedSince", { date: format.dateTime(new Date(row.blocked_at), { day: "numeric", month: "short", year: "numeric" }) })}
                    </span>
                  </span>
                </span>
                <button
                  type="button"
                  onClick={() => unblock.mutate(row.person.id)}
                  disabled={unblock.isPending}
                  className="min-h-11 shrink-0 rounded-2xl px-3 text-sm font-semibold disabled:opacity-50"
                  style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
                >
                  {t("unblock")}
                </button>
              </li>
            );
          })}
        </ul>
      )}
      <ErrorLine message={partnerErrorMessage(unblock.error, t, tUi)} />
    </div>
  );
}
