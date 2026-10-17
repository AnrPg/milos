"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { CLUBS_KEY } from "@/api/community";
import { redeemInvitation } from "@/api/organizations";
import { clientErrorMessage } from "@/components/client/errors";
import { clubInitials } from "@/components/community/community";
import { HubCard } from "@/components/member-app/HubParts";
import { OrganizationSelector } from "@/components/organization-selector";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";
import { parseJoinInput } from "@/lib/join-input";
import { useSelectedMembershipRole } from "@/lib/membership-role";

const STAFF_ROLES = new Set(["owner", "admin", "coach"]);

/**
 * Εγώ › Τα box και τα clubs μου › Box (mockup «myClubs»): the gyms you belong
 * to (the main one marked, switchable), and joining another by invitation
 * code or the gym's join link.
 */
export function MyGymsCard() {
  const t = useTranslations("Community");
  const { membership, memberships, isLoading } = useSelectedMembershipRole();

  return (
    <HubCard eyebrow={t("myGymsTitle")}>
      <div className="flex flex-col gap-4">
        {isLoading ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
        ) : memberships.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("myGymsEmpty")}</p>
        ) : (
          <ul className="flex flex-col gap-3">
            {memberships.map((entry) => {
              const name = entry.settings?.brand_name?.trim() || entry.organization.name;
              const main = entry.id === membership?.id;
              return (
                <li key={entry.id} className="flex items-center gap-3">
                  <span
                    aria-hidden="true"
                    className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-sm font-extrabold"
                    style={{ background: "var(--panel-raised)", color: "var(--text)" }}
                  >
                    {clubInitials(name)}
                  </span>
                  <div className="min-w-0 grow">
                    <p className="truncate font-bold" style={{ color: "var(--text)" }}>{name}</p>
                    <p className="text-xs" style={{ color: "var(--dim)" }}>
                      {STAFF_ROLES.has(entry.role) ? t("roleStaff") : t("roleMember")}
                    </p>
                  </div>
                  {main ? (
                    <span className="rounded-full px-3 py-1 text-xs font-semibold" style={{ color: "var(--primary)", border: "1px solid var(--primary)" }}>
                      {t("myGymsMain")}
                    </span>
                  ) : null}
                </li>
              );
            })}
          </ul>
        )}
        {memberships.length > 1 ? <OrganizationSelector variant="menu" /> : null}
        <JoinForm />
      </div>
    </HubCard>
  );
}

function JoinForm() {
  const t = useTranslations("Community");
  const tUi = useUiTranslations();
  const router = useRouter();
  const queryClient = useQueryClient();
  const { tokens } = useSession();
  const [value, setValue] = useState("");
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState<{ error: boolean; text: string } | null>(null);

  async function submit(event: FormEvent) {
    event.preventDefault();
    const input = parseJoinInput(value);
    if (!input) {
      setMessage({ error: true, text: t("joinInvalid") });
      return;
    }
    if (input.kind === "join") {
      router.push(`/join/${encodeURIComponent(input.slug)}`);
      return;
    }
    if (!tokens?.access_token) return;
    setPending(true);
    setMessage(null);
    try {
      const joined = await redeemInvitation(tokens.access_token, input.token);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ["organization-memberships"] }),
        queryClient.invalidateQueries({ queryKey: CLUBS_KEY }),
      ]);
      setValue("");
      setMessage({ error: false, text: t("joinDone", { name: joined.organization.name }) });
    } catch (caught) {
      setMessage({ error: true, text: clientErrorMessage(caught, tUi) });
    } finally {
      setPending(false);
    }
  }

  return (
    <form onSubmit={(event) => void submit(event)} className="flex flex-col gap-2">
      <label htmlFor="join-input" className="text-sm font-semibold" style={{ color: "var(--text)" }}>
        {t("joinLabel")}
      </label>
      <div className="flex gap-2">
        <input
          id="join-input"
          value={value}
          onChange={(event) => setValue(event.target.value)}
          placeholder={t("joinPlaceholder")}
          autoComplete="off"
          className="min-h-11 min-w-0 grow rounded-2xl px-3 text-sm"
          style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
        />
        <button
          type="submit"
          disabled={pending || !value.trim()}
          className="min-h-11 rounded-2xl px-4 text-sm font-semibold disabled:opacity-50"
          style={{ background: "var(--primary)", color: "var(--bg)" }}
        >
          {pending ? t("joinPending") : t("joinSubmit")}
        </button>
      </div>
      {message ? (
        <p role={message.error ? "alert" : "status"} className="text-xs" style={{ color: message.error ? "var(--danger, #dc2626)" : "var(--success)" }}>
          {message.text}
        </p>
      ) : null}
    </form>
  );
}
