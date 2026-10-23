"use client";

import { useEffect, useRef, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { addAccountProfile, type AccountProfile } from "@/api/account-profiles";
import { suggestHandle } from "@/api/auth";
import { cleanHandleInput, describeAccountError, profileSlotsLeft } from "@/components/account/account-model";
import { HandleField } from "@/components/account/HandleField";
import { PersonName } from "@/components/account/PersonName";
import {
  ACCOUNT_PROFILES_QUERY_KEY,
  useAccountProfiles,
  useSwitchProfile,
} from "@/components/account/use-account-profiles";
import { CollapsibleSection } from "@/components/profile/CollapsibleSection";
import { SemanticLabel } from "@/components/semantic-label";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useSession } from "@/components/session-provider";
import { Dialog } from "@/components/ui/Dialog";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

/**
 * Ρυθμίσεις › Profiles (ADR-187): one login (email + password) holds up to
 * three profiles. Lists them, switches to another, adds one while a slot is
 * free.
 */
export function ProfilesSection() {
  const t = useTranslations("accountProfiles");
  const profilesQuery = useAccountProfiles();
  const { switchTo, switchingTo, failed } = useSwitchProfile();
  const [adding, setAdding] = useState(false);

  const data = profilesQuery.data;
  const profiles = data?.profiles ?? [];
  const limit = data?.profile_limit ?? 3;
  const slotsLeft = profileSlotsLeft(profiles.length, limit);

  return (
    <CollapsibleSection
      id="profiles"
      title={t("profilesTitle")}
      description={data ? t("profilesCount", { count: profiles.length, limit }) : t("profilesDescription")}
    >
      <div className="space-y-4">
        {data ? (
          <p className="text-sm leading-6" style={{ color: "var(--muted)" }}>
            {t("profilesIntro", { email: data.email })}
          </p>
        ) : null}
        {profilesQuery.isError ? (
          <p className="text-sm font-semibold" style={{ color: "var(--danger)" }}>{t("profilesLoadError")}</p>
        ) : null}

        <ul className="space-y-2">
          {profiles.map((profile) => (
            <ProfileRow
              key={profile.id}
              profile={profile}
              switching={switchingTo === profile.id}
              disabled={Boolean(switchingTo)}
              onSwitch={() => void switchTo(profile.id)}
            />
          ))}
        </ul>
        {failed ? (
          <p className="text-sm font-semibold" style={{ color: "var(--danger)" }}>{t("switchError")}</p>
        ) : null}

        {data ? (
          slotsLeft > 0 ? (
            <button
              type="button"
              onClick={() => setAdding(true)}
              className="rounded-xl px-5 py-2.5 text-sm font-semibold"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            >
              {t("addProfile")}
            </button>
          ) : (
            <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{t("limitReached", { limit })}</p>
          )
        ) : null}
      </div>

      {adding ? <AddProfileDialog onClose={() => setAdding(false)} /> : null}
    </CollapsibleSection>
  );
}

function ProfileRow({
  profile,
  switching,
  disabled,
  onSwitch,
}: {
  profile: AccountProfile;
  switching: boolean;
  disabled: boolean;
  onSwitch: () => void;
}) {
  const t = useTranslations("accountProfiles");

  return (
    <li
      className="flex items-center gap-3 rounded-2xl px-4 py-3"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      <PersonAvatar name={profile.display_name} url={profile.avatar_url} size={40} />
      <div className="min-w-0 flex-1">
        <PersonName name={profile.display_name} handle={profile.handle} />
        <span className="text-[11px] uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
          <SemanticLabel value={profile.role} />
        </span>
      </div>
      {profile.current ? (
        <span
          className="shrink-0 rounded-full px-2.5 py-1 text-xs font-semibold"
          style={{ background: "color-mix(in srgb, var(--primary) 16%, transparent)", color: "var(--primary)" }}
        >
          {t("current")}
        </span>
      ) : (
        <button
          type="button"
          disabled={disabled}
          onClick={onSwitch}
          className="min-h-11 shrink-0 rounded-xl px-3 text-sm font-semibold disabled:opacity-50"
          style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
        >
          {switching ? t("switching") : t("switch")}
        </button>
      )}
    </li>
  );
}

function AddProfileDialog({ onClose }: { onClose: () => void }) {
  const t = useTranslations("accountProfiles");
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const [displayName, setDisplayName] = useState("");
  const [handle, setHandle] = useState("");
  const [role, setRole] = useState<"member" | "athlete">("member");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const handleEdited = useRef(false);

  // Until the person types a handle, suggest one from the display name.
  useEffect(() => {
    const name = displayName.trim();
    if (handleEdited.current || !name) return;
    const controller = new AbortController();
    const timer = window.setTimeout(() => {
      suggestHandle(name, controller.signal)
        .then((result) => {
          if (!handleEdited.current && result.handle) setHandle(result.handle);
        })
        .catch(() => undefined);
    }, 400);
    return () => {
      window.clearTimeout(timer);
      controller.abort();
    };
  }, [displayName]);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!tokens || pending) return;
    const cleaned = cleanHandleInput(handle);
    if (!cleaned) {
      setError(t("handleRules"));
      return;
    }
    setPending(true);
    setError(null);
    try {
      const result = await addAccountProfile(tokens.access_token, {
        handle: cleaned,
        display_name: displayName.trim() || undefined,
        role,
      });
      queryClient.setQueriesData({ queryKey: ACCOUNT_PROFILES_QUERY_KEY }, result);
      onClose();
    } catch (err) {
      const described = describeAccountError(err);
      setError(described ? t(described.key, described.values) : localizeError(err, i18n));
      setPending(false);
    }
  }

  const inputStyle = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" };

  return (
    <Dialog
      onClose={onClose}
      title={t("addProfileTitle")}
      description={t("addProfileHint")}
      size="md"
      dismissible={!pending}
      onSubmit={(event) => void submit(event)}
      footer={
        <div className="flex w-full gap-3 sm:w-auto">
          <button
            type="button"
            onClick={onClose}
            disabled={pending}
            className="flex-1 rounded-xl px-5 py-2.5 text-sm font-semibold sm:flex-none"
            style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
          >
            {t("cancel")}
          </button>
          <button
            type="submit"
            disabled={pending || !handle.trim()}
            className="flex-1 rounded-xl px-5 py-2.5 text-sm font-semibold disabled:opacity-50 sm:flex-none"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {pending ? t("adding") : t("addProfileSubmit")}
          </button>
        </div>
      }
    >
      <div className="space-y-4">
        <div className="space-y-1.5">
          <label
            htmlFor="new-profile-display-name"
            className="block text-xs font-semibold uppercase tracking-[0.18em]"
            style={{ color: "var(--muted)" }}
          >
            {t("displayNameLabel")}
          </label>
          <input
            id="new-profile-display-name"
            value={displayName}
            onChange={(event) => setDisplayName(event.target.value)}
            maxLength={50}
            autoComplete="nickname"
            className="w-full rounded-xl px-4 py-2.5 text-sm outline-none"
            style={inputStyle}
          />
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t("displayNameHint")}</p>
        </div>

        <HandleField
          value={handle}
          onChange={(next) => {
            handleEdited.current = true;
            setHandle(next);
          }}
          hint={t("handleHint")}
        />

        <fieldset className="space-y-1.5">
          <legend className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--muted)" }}>
            {t("roleLabel")}
          </legend>
          <div className="grid grid-cols-2 gap-2" role="radiogroup" aria-label={t("roleLabel")}>
            {(["member", "athlete"] as const).map((option) => {
              const selected = role === option;
              return (
                <button
                  key={option}
                  type="button"
                  role="radio"
                  aria-checked={selected}
                  onClick={() => setRole(option)}
                  className="min-h-11 rounded-xl px-3 py-2 text-start text-sm"
                  style={{
                    background: selected ? "color-mix(in srgb, var(--primary) 14%, transparent)" : "var(--panel-muted)",
                    border: `1px solid ${selected ? "var(--primary)" : "var(--border)"}`,
                    color: "var(--text)",
                  }}
                >
                  <span className="block font-semibold">
                    <SemanticLabel value={option} />
                  </span>
                  <span className="block text-xs" style={{ color: "var(--dim)" }}>
                    {option === "member" ? t("roleMemberHint") : t("roleAthleteHint")}
                  </span>
                </button>
              );
            })}
          </div>
        </fieldset>

        {error ? (
          <p className="text-sm font-semibold" style={{ color: "var(--danger)" }}>{error}</p>
        ) : null}
      </div>
    </Dialog>
  );
}
