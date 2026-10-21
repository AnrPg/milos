"use client";

import Link from "next/link";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { CLUBS_KEY, FEED_KEY } from "@/api/community";
import {
  answerSquadInvite,
  createSquad,
  fetchSquads,
  inviteToSquad,
  reopenSquad,
  squadKey,
  squadsKey,
  type PtSquad,
  type PtSquadMember,
  type PtSquadPerson,
} from "@/api/squads";
import { clientErrorMessage } from "@/components/client/errors";
import { Badge } from "@/components/community/MembersTab";
import { Field, inputStyle } from "@/components/community/ProposeGroupSheet";
import { ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { useSession } from "@/components/session-provider";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useUiTranslations } from "@/i18n/ui";

import { invitableClients, matchesQuery, squadHref } from "./squads";

/** The person's squads in one gym (ADR-168). */
export function useSquads(slug: string | null | undefined) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  return useQuery({
    queryKey: squadsKey(slug ?? ""),
    enabled: Boolean(token && slug),
    queryFn: () => fetchSquads(token!, slug!),
  });
}

/** Everything a squad change can move: the lists, the squad, the clubs and the feed. */
export function useSquadRefresh(slug: string, squadId?: string) {
  const queryClient = useQueryClient();
  return () =>
    Promise.all([
      queryClient.invalidateQueries({ queryKey: squadsKey(slug) }),
      squadId ? queryClient.invalidateQueries({ queryKey: squadKey(squadId) }) : Promise.resolve(),
      queryClient.invalidateQueries({ queryKey: CLUBS_KEY }),
      queryClient.invalidateQueries({ queryKey: FEED_KEY }),
    ]);
}

/** One squad in a list: its name, coach or size, and how the person stands in it. */
export function SquadRow({ squad, clubId, slug }: { squad: PtSquad; clubId: string | null; slug: string }) {
  const t = useTranslations("Squads");
  const detail =
    squad.role === "coach"
      ? [t("members", { count: squad.member_count }), squad.invite_count > 0 ? t("invitesOpen", { count: squad.invite_count }) : null]
      : [t("coachedBy", { coach: squad.coach.nickname ?? "?" })];
  const body = (
    <>
      <span className="block truncate font-bold" style={{ color: "var(--text)" }}>{squad.name}</span>
      <span className="block truncate text-xs" style={{ color: "var(--dim)" }}>
        {detail.filter(Boolean).join(" · ")}
      </span>
    </>
  );
  return (
    <li className="flex min-h-14 items-center gap-3 py-2">
      {squad.archived_at ? (
        <div className="min-w-0 grow">{body}</div>
      ) : clubId ? (
        <Link href={squadHref(clubId, squad.id)} className="min-w-0 grow">
          {body}
        </Link>
      ) : (
        <div className="min-w-0 grow">{body}</div>
      )}
      {squad.archived_at ? <ReopenButton squad={squad} slug={slug} /> : squad.role === "coach" ? <Badge muted>{t("coachLabel")}</Badge> : null}
    </li>
  );
}

function ReopenButton({ squad, slug }: { squad: PtSquad; slug: string }) {
  const t = useTranslations("Squads");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const refresh = useSquadRefresh(slug, squad.id);
  const reopen = useMutation({ mutationFn: () => reopenSquad(tokens!.access_token, slug, squad.id), onSuccess: refresh });
  return (
    <div className="flex shrink-0 flex-col items-end">
      <SmallAction disabled={reopen.isPending} onClick={() => reopen.mutate()}>{t("reopen")}</SmallAction>
      <ErrorLine message={reopen.error ? clientErrorMessage(reopen.error, tUi) : null} />
    </div>
  );
}

/** An invitation waiting for the person: who it is from, «Μπες» or «Όχι». */
export function InvitationRow({ squad, slug }: { squad: PtSquad; slug: string }) {
  const t = useTranslations("Squads");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const refresh = useSquadRefresh(slug, squad.id);
  const answer = useMutation({
    mutationFn: (accept: boolean) => answerSquadInvite(tokens!.access_token, slug, squad.id, accept),
    onSuccess: refresh,
  });
  return (
    <li className="flex flex-col gap-1 py-2" data-testid="squad-invite">
      <div className="flex min-h-14 items-center gap-3">
        <PersonAvatar name={squad.coach.nickname} url={squad.coach.avatar_url} />
        <div className="min-w-0 grow">
          <span className="block truncate font-bold" style={{ color: "var(--text)" }}>{squad.name}</span>
          <span className="block truncate text-xs" style={{ color: "var(--dim)" }}>
            {t("invitedBy", { coach: squad.coach.nickname ?? "?" })}
          </span>
        </div>
        <SmallAction disabled={answer.isPending} onClick={() => answer.mutate(false)}>{t("decline")}</SmallAction>
        <SmallAction primary disabled={answer.isPending} onClick={() => answer.mutate(true)}>{t("accept")}</SmallAction>
      </div>
      <ErrorLine message={answer.error ? clientErrorMessage(answer.error, tUi) : null} />
    </li>
  );
}

/** Picking clients by name: a search box over a checklist. */
function ClientPicker({
  clients,
  selected,
  onToggle,
  max,
}: {
  clients: PtSquadPerson[];
  selected: Set<string>;
  onToggle: (id: string) => void;
  max: number;
}) {
  const t = useTranslations("Squads");
  const [query, setQuery] = useState("");
  const shown = clients.filter((client) => matchesQuery(client, query));
  return (
    <fieldset className="flex flex-col gap-2">
      <legend className="mb-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
        {t("pickClients")} · {t("placesLeft", { count: Math.max(0, max - selected.size) })}
      </legend>
      {clients.length > 6 ? (
        <input
          aria-label={t("searchClients")}
          placeholder={t("searchClients")}
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          className="min-h-11 rounded-2xl px-3 text-sm"
          style={inputStyle}
        />
      ) : null}
      <ul className="flex max-h-72 flex-col overflow-y-auto">
        {shown.map((client) => {
          const checked = selected.has(client.id);
          return (
            <li key={client.id}>
              <label className="flex min-h-12 cursor-pointer items-center gap-3">
                <input
                  type="checkbox"
                  checked={checked}
                  disabled={!checked && selected.size >= max}
                  onChange={() => onToggle(client.id)}
                  className="h-5 w-5"
                />
                <PersonAvatar name={client.nickname} url={client.avatar_url} />
                <span className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{client.nickname ?? "?"}</span>
              </label>
            </li>
          );
        })}
      </ul>
    </fieldset>
  );
}

function useSelection() {
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const toggle = (id: string) =>
    setSelected((current) => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  return { selected, toggle };
}

/** «Νέο squad»: a name, an optional line about it, and which clients to invite. */
export function CreateSquadSheet({
  slug,
  clients,
  maxMembers,
  onClose,
}: {
  slug: string;
  clients: PtSquadPerson[];
  maxMembers: number;
  onClose: () => void;
}) {
  const t = useTranslations("Squads");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const refresh = useSquadRefresh(slug);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const { selected, toggle } = useSelection();
  const create = useMutation({
    mutationFn: () =>
      createSquad(tokens!.access_token, slug, {
        name: name.trim(),
        description: description.trim() || null,
        client_ids: [...selected],
      }),
    onSuccess: async () => {
      await refresh();
      onClose();
    },
  });
  const valid = name.trim().length >= 2;

  return (
    <Sheet
      labelId="create-squad"
      eyebrow={t("label")}
      title={t("newSquad")}
      onClose={onClose}
      footer={
        <>
          <SheetButton onClick={onClose}>{t("cancel")}</SheetButton>
          <SheetButton primary type="submit" form="create-squad-form" disabled={!valid || create.isPending}>
            {t("create")}
          </SheetButton>
        </>
      }
    >
      <form
        id="create-squad-form"
        className="flex flex-col gap-3"
        onSubmit={(event) => {
          event.preventDefault();
          if (valid) create.mutate();
        }}
      >
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("newSquadHint")}</p>
        <Field label={t("name")}>
          <input
            value={name}
            maxLength={60}
            placeholder={t("namePlaceholder")}
            onChange={(event) => setName(event.target.value)}
            className="min-h-11 rounded-2xl px-3 text-sm font-normal"
            style={inputStyle}
          />
        </Field>
        <Field label={t("about")}>
          <input
            value={description}
            maxLength={200}
            onChange={(event) => setDescription(event.target.value)}
            className="min-h-11 rounded-2xl px-3 text-sm font-normal"
            style={inputStyle}
          />
        </Field>
        {clients.length > 0 ? (
          <ClientPicker clients={invitableClients(clients)} selected={selected} onToggle={toggle} max={maxMembers} />
        ) : (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("noClients")}</p>
        )}
        <ErrorLine message={create.error ? clientErrorMessage(create.error, tUi) : null} />
      </form>
    </Sheet>
  );
}

/** The coach invites more of their clients into a squad. */
export function InviteClientsSheet({
  slug,
  squad,
  members,
  clients,
  seats,
  onClose,
}: {
  slug: string;
  squad: PtSquad;
  members: PtSquadMember[];
  clients: PtSquadPerson[];
  seats: number;
  onClose: () => void;
}) {
  const t = useTranslations("Squads");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const refresh = useSquadRefresh(slug, squad.id);
  const { selected, toggle } = useSelection();
  const candidates = invitableClients(clients, members);
  const invite = useMutation({
    mutationFn: () => inviteToSquad(tokens!.access_token, slug, squad.id, [...selected]),
    onSuccess: async () => {
      await refresh();
      onClose();
    },
  });

  return (
    <Sheet
      labelId="invite-squad"
      eyebrow={squad.name}
      title={t("inviteTitle")}
      onClose={onClose}
      footer={
        <>
          <SheetButton onClick={onClose}>{t("cancel")}</SheetButton>
          <SheetButton primary disabled={selected.size === 0 || invite.isPending} onClick={() => invite.mutate()}>
            {t("invite")}
          </SheetButton>
        </>
      }
    >
      <div className="flex flex-col gap-3">
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("followsCoaching")}</p>
        {candidates.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{clients.length === 0 ? t("noClients") : t("noMoreClients")}</p>
        ) : (
          <ClientPicker clients={candidates} selected={selected} onToggle={toggle} max={seats} />
        )}
        <ErrorLine message={invite.error ? clientErrorMessage(invite.error, tUi) : null} />
      </div>
    </Sheet>
  );
}

export function SmallAction({
  children,
  onClick,
  primary,
  disabled,
}: {
  children: string;
  onClick: () => void;
  primary?: boolean;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="min-h-11 shrink-0 rounded-full px-4 text-sm font-semibold disabled:opacity-50"
      style={{
        background: primary ? "var(--primary)" : "var(--panel-raised)",
        color: primary ? "var(--bg)" : "var(--text)",
        border: primary ? "none" : "1px solid var(--border)",
      }}
    >
      {children}
    </button>
  );
}
