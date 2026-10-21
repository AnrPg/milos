"use client";

import Link from "next/link";
import { useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  answerClubRequest,
  archiveOpenClub,
  createOpenClub,
  fetchStaffClub,
  fetchStaffClubs,
  removeClubMember,
  STAFF_CLUBS_KEY,
  staffClubKey,
  updateOpenClub,
  type StaffOpenClub,
} from "@/api/admin-community";
import { CLUBS_KEY, type OpenClubJoinPolicy } from "@/api/community";
import { clientErrorMessage } from "@/components/client/errors";
import { SmallButton } from "@/components/community/GroupPage";
import { Field, inputStyle } from "@/components/community/ProposeGroupSheet";
import { ChoicePill, ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { useSession } from "@/components/session-provider";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useUiTranslations } from "@/i18n/ui";
import { BoxPhotoUploadError, uploadBoxPhoto } from "@/lib/box-photo-upload";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";

/**
 * Ανοιχτά clubs (board 7 Q6): clubs the box runs that anyone who follows or
 * belongs to it can join with «Μπες» (or ask, when they need approval). Each
 * has a cover, #ανακοινώσεις and #γενικά, and shows on the box page.
 */
export function OpenClubsTab() {
  const t = useTranslations("CommunityAdmin");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const { membership } = useSelectedMembershipRole();
  const manage = can(membership, "manage_community");
  const clubs = useQuery({ queryKey: STAFF_CLUBS_KEY, enabled: Boolean(token), queryFn: () => fetchStaffClubs(token) });
  const [editing, setEditing] = useState<StaffOpenClub | "new" | null>(null);
  const [openId, setOpenId] = useState<string | null>(null);

  if (!clubs.data) return <p style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  return (
    <>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("clubsHint")}</p>
      {manage ? (
        <button
          type="button"
          onClick={() => setEditing("new")}
          className="min-h-11 rounded-2xl text-sm font-bold"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          + {t("clubNew")}
        </button>
      ) : null}
      {clubs.data.length === 0 ? (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("clubsEmpty")}</p>
      ) : (
        <ul className="flex flex-col gap-3">
          {clubs.data.map((club) => (
            <li key={club.id} className="overflow-hidden rounded-3xl" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
              {club.cover_url ? (
                // eslint-disable-next-line @next/next/no-img-element -- gym-uploaded media origin
                <img src={club.cover_url} alt="" className="aspect-[16/5] w-full object-cover" />
              ) : null}
              <button
                type="button"
                aria-expanded={openId === club.id}
                onClick={() => setOpenId(openId === club.id ? null : club.id)}
                className="flex w-full items-center gap-3 px-4 py-3 text-left"
              >
                <span className="min-w-0 grow">
                  <span className="block font-bold" style={{ color: "var(--text)" }}>{club.name}</span>
                  <span className="block text-xs" style={{ color: "var(--dim)" }}>
                    {[
                      t("members", { count: club.member_count }),
                      club.join_policy === "approval" ? t("clubApproval") : t("clubOpen"),
                      club.request_count ? t("requests", { count: club.request_count }) : null,
                    ]
                      .filter(Boolean)
                      .join(" · ")}
                  </span>
                </span>
                <span aria-hidden="true" style={{ color: "var(--dim)" }}>{openId === club.id ? "▴" : "▾"}</span>
              </button>
              {openId === club.id ? <ClubDetail clubId={club.id} manage={manage} onEdit={() => setEditing(club)} /> : null}
            </li>
          ))}
        </ul>
      )}
      {editing ? <OpenClubEditor club={editing === "new" ? null : editing} onClose={() => setEditing(null)} /> : null}
    </>
  );
}

function useClubsRefresh() {
  const queryClient = useQueryClient();
  return () =>
    Promise.all([
      queryClient.invalidateQueries({ queryKey: STAFF_CLUBS_KEY }),
      queryClient.invalidateQueries({ queryKey: CLUBS_KEY }),
    ]);
}

function ClubDetail({ clubId, manage, onEdit }: { clubId: string; manage: boolean; onEdit: () => void }) {
  const t = useTranslations("CommunityAdmin");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const refresh = useClubsRefresh();
  const [archiving, setArchiving] = useState(false);
  const club = useQuery({ queryKey: staffClubKey(clubId), enabled: Boolean(token), queryFn: () => fetchStaffClub(token, clubId) });
  const act = useMutation({
    mutationFn: ({ userId, action }: { userId: string; action: "approve" | "decline" | "remove" }) =>
      action === "remove" ? removeClubMember(token, clubId, userId) : answerClubRequest(token, clubId, userId, action === "approve"),
    onSuccess: async () => {
      await Promise.all([club.refetch(), refresh()]);
    },
  });
  const archive = useMutation({
    mutationFn: () => archiveOpenClub(token, clubId),
    onSuccess: async () => {
      setArchiving(false);
      await refresh();
    },
  });

  if (!club.data) return <p className="px-4 pb-4 text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  const requests = club.data.requests ?? [];
  const members = club.data.members ?? [];

  return (
    <div className="flex flex-col gap-3 border-t px-4 py-3" style={{ borderColor: "var(--border)" }}>
      {club.data.description ? <p className="whitespace-pre-wrap text-sm" style={{ color: "var(--text-soft)" }}>{club.data.description}</p> : null}
      <div className="flex flex-wrap gap-2">
        <Link
          href={`/clubs/${clubId}`}
          className="flex min-h-11 items-center rounded-full px-4 text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("clubOpenPage")}
        </Link>
        {manage ? <SmallButton onClick={onEdit}>{t("clubEdit")}</SmallButton> : null}
        {manage ? <SmallButton onClick={() => setArchiving(true)}>{t("clubArchive")}</SmallButton> : null}
      </div>
      {requests.length > 0 ? (
        <div className="flex flex-col gap-1">
          <p className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>
            {t("requests", { count: requests.length })}
          </p>
          <ul className="flex flex-col">
            {requests.map((row) => (
              <li key={row.person.id} className="flex min-h-12 items-center gap-3 py-1">
                <PersonAvatar name={row.person.nickname} url={row.person.avatar_url} size={32} />
                <span className="min-w-0 grow truncate text-sm font-bold" style={{ color: "var(--text)" }}>{row.person.nickname ?? "?"}</span>
                <SmallButton disabled={act.isPending} onClick={() => act.mutate({ userId: row.person.id, action: "decline" })}>{t("decline")}</SmallButton>
                <SmallButton primary disabled={act.isPending} onClick={() => act.mutate({ userId: row.person.id, action: "approve" })}>{t("approve")}</SmallButton>
              </li>
            ))}
          </ul>
        </div>
      ) : null}
      <div className="flex flex-col gap-1">
        <p className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>
          {t("members", { count: members.length })}
        </p>
        {members.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("clubNoMembers")}</p>
        ) : (
          <ul className="flex flex-col">
            {members.map((row) => (
              <li key={row.person.id} className="flex min-h-12 items-center gap-3 py-1">
                <PersonAvatar name={row.person.nickname} url={row.person.avatar_url} size={32} />
                <span className="min-w-0 grow truncate text-sm font-bold" style={{ color: "var(--text)" }}>{row.person.nickname ?? "?"}</span>
                <SmallButton disabled={act.isPending} onClick={() => act.mutate({ userId: row.person.id, action: "remove" })}>{t("remove")}</SmallButton>
              </li>
            ))}
          </ul>
        )}
      </div>
      <ErrorLine message={act.error ? clientErrorMessage(act.error, tUi) : null} />
      {archiving ? (
        <Sheet
          labelId="archive-club"
          eyebrow={club.data.name}
          title={t("clubArchiveTitle")}
          onClose={() => setArchiving(false)}
          footer={
            <>
              <SheetButton onClick={() => setArchiving(false)}>{t("cancel")}</SheetButton>
              <SheetButton primary disabled={archive.isPending} onClick={() => archive.mutate()}>{t("clubArchive")}</SheetButton>
            </>
          }
        >
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("clubArchiveBody")}</p>
          <ErrorLine message={archive.error ? clientErrorMessage(archive.error, tUi) : null} />
        </Sheet>
      ) : null}
    </div>
  );
}

/** Create or edit an open club: name, what it is, a cover photo and how people get in. */
function OpenClubEditor({ club, onClose }: { club: StaffOpenClub | null; onClose: () => void }) {
  const t = useTranslations("CommunityAdmin");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const refresh = useClubsRefresh();
  const fileInput = useRef<HTMLInputElement>(null);
  const [name, setName] = useState(club?.name ?? "");
  const [description, setDescription] = useState(club?.description ?? "");
  const [policy, setPolicy] = useState<OpenClubJoinPolicy>(club?.join_policy ?? "open");
  const [cover, setCover] = useState<{ id: string | null; url: string | null }>({
    id: club?.cover_media_id ?? null,
    url: club?.cover_url ?? null,
  });
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);

  const save = useMutation({
    mutationFn: () => {
      const draft = { name: name.trim(), description: description.trim() || null, join_policy: policy, cover_media_id: cover.id };
      return club ? updateOpenClub(token, club.id, draft) : createOpenClub(token, draft);
    },
    onSuccess: async (saved) => {
      queryClient.setQueryData(staffClubKey(saved.id), saved);
      await refresh();
      onClose();
    },
  });

  async function pick(file: File | undefined) {
    if (!file) return;
    setUploading(true);
    setUploadError(null);
    try {
      const media = await uploadBoxPhoto(token, file);
      setCover({ id: media.id, url: media.url ?? null });
    } catch (caught) {
      setUploadError(caught instanceof BoxPhotoUploadError ? t(`upload_${caught.reason}`) : clientErrorMessage(caught, tUi));
    } finally {
      setUploading(false);
    }
  }

  return (
    <Sheet
      labelId="open-club-editor"
      title={club ? t("clubEdit") : t("clubNew")}
      onClose={onClose}
      footer={
        <>
          <SheetButton onClick={onClose}>{t("cancel")}</SheetButton>
          <SheetButton primary type="submit" form="open-club-form" disabled={!name.trim() || uploading || save.isPending}>
            {club ? t("save") : t("create")}
          </SheetButton>
        </>
      }
    >
      <form
        id="open-club-form"
        className="flex flex-col gap-3"
        onSubmit={(event) => {
          event.preventDefault();
          if (name.trim()) save.mutate();
        }}
      >
        <div className="flex flex-col gap-2">
          {cover.url ? (
            // eslint-disable-next-line @next/next/no-img-element -- gym-uploaded media origin
            <img src={cover.url} alt="" className="aspect-[16/6] w-full rounded-2xl object-cover" />
          ) : (
            <div className="flex aspect-[16/6] w-full items-center justify-center rounded-2xl text-sm" style={{ background: "var(--panel-raised)", color: "var(--dim)" }}>
              {t("coverNone")}
            </div>
          )}
          <div className="flex gap-2">
            <SmallButton disabled={uploading} onClick={() => fileInput.current?.click()}>
              {uploading ? t("uploading") : cover.url ? t("coverChange") : t("coverAdd")}
            </SmallButton>
            {cover.id ? <SmallButton onClick={() => setCover({ id: null, url: null })}>{t("coverRemove")}</SmallButton> : null}
          </div>
          <input
            ref={fileInput}
            type="file"
            accept="image/*"
            className="sr-only"
            aria-label={t("coverAdd")}
            onChange={(event) => void pick(event.target.files?.[0])}
          />
          <ErrorLine message={uploadError} />
        </div>
        <Field label={t("clubName")}>
          <input value={name} maxLength={80} required onChange={(event) => setName(event.target.value)} placeholder={t("clubNamePlaceholder")} className="min-h-11 rounded-2xl px-3 text-sm font-normal" style={inputStyle} />
        </Field>
        <Field label={t("clubAbout")}>
          <textarea
            value={description}
            maxLength={1000}
            rows={3}
            onChange={(event) => setDescription(event.target.value)}
            placeholder={t("clubAboutPlaceholder")}
            className="rounded-2xl px-3 py-2 text-sm font-normal"
            style={inputStyle}
          />
        </Field>
        <fieldset className="flex flex-col gap-1">
          <legend className="mb-1 text-sm font-semibold" style={{ color: "var(--text)" }}>{t("clubWhoJoins")}</legend>
          <div role="radiogroup" aria-label={t("clubWhoJoins")} className="flex gap-2">
            <ChoicePill selected={policy === "open"} onSelect={() => setPolicy("open")} hint={t("clubOpenHint")}>{t("clubOpen")}</ChoicePill>
            <ChoicePill selected={policy === "approval"} onSelect={() => setPolicy("approval")} hint={t("clubApprovalHint")}>{t("clubApproval")}</ChoicePill>
          </div>
        </fieldset>
        <ErrorLine message={save.error ? clientErrorMessage(save.error, tUi) : null} />
      </form>
    </Sheet>
  );
}
