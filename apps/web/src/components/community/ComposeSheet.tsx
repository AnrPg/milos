"use client";

import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { createPost, FEED_KEY, type AttachmentType, type CommunityClub } from "@/api/community";
import { createProfilePost, SUMMARY_KEY } from "@/api/social";
import { fetchJournalPage, typedItem, type TypedJournalItem } from "@/api/journal";
import { clientErrorMessage } from "@/components/client/errors";
import { formatDateTime } from "@/components/client/format";
import {
  attachmentTypeOf,
  channelName,
  composeTargetGroups,
  initialComposeTarget,
  newOperationId,
  sameTarget,
  type ComposeTarget,
} from "@/components/community/community";
import { formatScore } from "@/components/pantheon/PantheonCard";
import { useSession } from "@/components/session-provider";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";

/**
 * ⊕ button that opens compose (vision §7.1). Everyone can post: to a club
 * channel, or to their own profile for followers or everyone (ADR-142).
 */
export function ComposeButton({
  clubs,
  clubId,
  channelId,
}: {
  clubs: CommunityClub[];
  clubId?: string | null;
  channelId?: string | null;
}) {
  const t = useTranslations("Community");
  const [open, setOpen] = useState(false);
  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-label={t("compose")}
        className="flex h-11 w-11 items-center justify-center rounded-full"
        style={{ background: "var(--primary)", color: "var(--bg)" }}
      >
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" aria-hidden="true">
          <path d="M12 5v14M5 12h14" />
        </svg>
      </button>
      {open ? <ComposeSheet clubs={clubs} clubId={clubId} channelId={channelId} onClose={() => setOpen(false)} /> : null}
    </>
  );
}

const SHAREABLE_KINDS = ["execution", "training_log", "pr"] as const;
const LAST_TARGET_KEY = "milos:compose-target";
const PUBLIC_NOTE_KEY = "milos:compose-public-note-seen";

function readStored<T>(key: string): T | null {
  try {
    const raw = window.localStorage.getItem(key);
    return raw ? (JSON.parse(raw) as T) : null;
  } catch {
    return null;
  }
}

function writeStored(key: string, value: unknown) {
  try {
    window.localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // Remembering is a convenience; posting works without it.
  }
}

function isPublic(target: ComposeTarget) {
  return target.kind === "profile" ? target.audience === "public" : target.public;
}

function ComposeSheet({
  clubs,
  clubId,
  channelId,
  onClose,
}: {
  clubs: CommunityClub[];
  clubId?: string | null;
  channelId?: string | null;
  onClose: () => void;
}) {
  const t = useTranslations("Community");
  const tUi = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const trapRef = useModalFocusTrap<HTMLDivElement>(onClose);
  const groups = composeTargetGroups(clubs);
  const [target, setTarget] = useState<ComposeTarget>(() =>
    initialComposeTarget(clubs, readStored<ComposeTarget>(LAST_TARGET_KEY), clubId, channelId),
  );
  const [picking, setPicking] = useState(false);
  const [publicNoteSeen, setPublicNoteSeen] = useState(() => readStored<boolean>(PUBLIC_NOTE_KEY) === true);
  const [body, setBody] = useState("");
  const [attachment, setAttachment] = useState<{ type: AttachmentType; id: string } | null>(null);
  const [operationId] = useState(newOperationId);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const entries = useQuery({
    queryKey: ["community", "attachable"],
    enabled: Boolean(token),
    queryFn: () => fetchJournalPage(token!, { kinds: [...SHAREABLE_KINDS], limit: 10 }),
  });
  const attachable = useMemo(() => (entries.data?.items ?? []).map(typedItem), [entries.data]);
  const channelTarget =
    target.kind === "channel"
      ? groups.flatMap((group) => group.channels.map((channel) => ({ club: group.club, channel }))).find(
          (option) => option.channel.id === target.channelId,
        )
      : undefined;
  const ready = target.kind === "profile" || Boolean(channelTarget);
  const showPublicNote = isPublic(target) && !publicNoteSeen;

  function targetLabel(value: ComposeTarget) {
    if (value.kind === "profile") return value.audience === "public" ? t("audiencePublic") : t("audienceFollowers");
    if (!channelTarget) return "";
    return value.public
      ? t("audienceBoxPublic", { club: channelTarget.club.name })
      : `${channelTarget.club.name} › #${channelName(channelTarget.channel, t)}`;
  }

  async function publish() {
    if (!token || !ready || busy || (!body.trim() && !attachment)) return;
    setBusy(true);
    setError(null);
    const content = {
      body: body.trim() || undefined,
      attachment_type: attachment?.type,
      attachment_id: attachment?.id,
      client_operation_id: operationId,
    };
    try {
      if (target.kind === "profile") {
        await createProfilePost(token, { audience: target.audience, ...content });
        await queryClient.invalidateQueries({ queryKey: SUMMARY_KEY });
      } else if (channelTarget) {
        await createPost(token, {
          channel_id: channelTarget.channel.id,
          audience: target.public ? "public" : "club_channel",
          ...content,
        });
      }
      writeStored(LAST_TARGET_KEY, target);
      if (isPublic(target)) writeStored(PUBLIC_NOTE_KEY, true);
      await queryClient.invalidateQueries({ queryKey: FEED_KEY });
      onClose();
    } catch (caught) {
      setError(clientErrorMessage(caught, tUi));
      setBusy(false);
    }
  }

  return (
    <div
      className="fixed inset-0 z-[60] flex items-end justify-center sm:items-center"
      style={{ background: "rgba(0, 0, 0, 0.45)" }}
      onClick={onClose}
    >
      <div
        ref={trapRef}
        role="dialog"
        aria-modal="true"
        aria-label={t("compose")}
        className="flex max-h-[90vh] w-full max-w-md flex-col gap-4 overflow-y-auto rounded-t-3xl p-5 sm:rounded-3xl"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", paddingBottom: "calc(1.25rem + env(safe-area-inset-bottom))" }}
        onClick={(event) => event.stopPropagation()}
      >
        <h2 className="text-lg font-extrabold" style={{ color: "var(--text)" }}>{t("compose")}</h2>
        <label className="sr-only" htmlFor="compose-body">{t("composePlaceholder")}</label>
        <textarea
          id="compose-body"
          value={body}
          maxLength={5000}
          rows={4}
          onChange={(event) => setBody(event.target.value)}
          placeholder={t("composePlaceholder")}
          className="rounded-2xl p-3 text-sm"
          style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
        />

        <fieldset className="flex flex-col gap-2">
          <legend className="mb-1 text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {t("composeAttach")}
          </legend>
          <Choice name="attachment" checked={!attachment} onChange={() => setAttachment(null)} label={t("composeAttachNone")} />
          {entries.isSuccess && attachable.length === 0 ? (
            <p className="text-sm" style={{ color: "var(--dim)" }}>{t("composeAttachEmpty")}</p>
          ) : null}
          {attachable.map((item) => {
            const type = attachmentTypeOf(item.kind);
            if (!type) return null;
            return (
              <Choice
                key={`${item.kind}:${item.id}`}
                name="attachment"
                checked={attachment?.id === item.id}
                onChange={() => setAttachment({ type, id: item.id })}
                label={entryLabel(item, t)}
                hint={formatDateTime(item.occurred_at, locale)}
              />
            );
          })}
        </fieldset>

        <button
          type="button"
          onClick={() => setPicking(true)}
          aria-haspopup="dialog"
          className="flex min-h-12 items-center justify-between gap-3 rounded-2xl px-3 text-start"
          style={{ border: "1px solid var(--border)" }}
        >
          <span className="flex min-w-0 flex-col">
            <span className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
              {t("composeWhere")}
            </span>
            <span className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{targetLabel(target)}</span>
          </span>
          <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
        </button>
        {showPublicNote ? (
          <p role="note" className="rounded-2xl p-3 text-sm" style={{ background: "var(--panel-raised)", color: "var(--text-soft)" }}>
            {t("publicNote")}{" "}
            <button
              type="button"
              className="font-semibold underline"
              style={{ color: "var(--text)" }}
              onClick={() => {
                writeStored(PUBLIC_NOTE_KEY, true);
                setPublicNoteSeen(true);
              }}
            >
              {t("publicNoteOk")}
            </button>
          </p>
        ) : null}

        {error ? <p role="alert" className="text-sm" style={{ color: "var(--danger, #dc2626)" }}>{error}</p> : null}
        <div className="flex gap-2">
          <button
            type="button"
            onClick={onClose}
            className="min-h-12 flex-1 rounded-2xl text-sm font-semibold"
            style={{ border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {t("cancel")}
          </button>
          <button
            type="button"
            onClick={() => void publish()}
            disabled={busy || !ready || (!body.trim() && !attachment)}
            className="min-h-12 flex-1 rounded-2xl text-sm font-bold disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--bg)" }}
          >
            {busy ? t("publishing") : t("publish")}
          </button>
        </div>
      </div>
      {picking ? (
        <AudienceSheet
          groups={groups}
          selected={target}
          onPick={(value) => {
            setTarget(value);
            setPicking(false);
          }}
          onClose={() => setPicking(false)}
        />
      ) : null}
    </div>
  );
}

/**
 * «Ποιος το βλέπει» (plan §5a Q13): channels grouped by club, then the
 * profile audiences, each saying who sees it.
 */
function AudienceSheet({
  groups,
  selected,
  onPick,
  onClose,
}: {
  groups: ReturnType<typeof composeTargetGroups>;
  selected: ComposeTarget;
  onPick: (target: ComposeTarget) => void;
  onClose: () => void;
}) {
  const t = useTranslations("Community");
  const trapRef = useModalFocusTrap<HTMLDivElement>(onClose);
  const option = (target: ComposeTarget, label: string, hint: string, key: string) => (
    <Choice key={key} name="audience" checked={sameTarget(target, selected)} onChange={() => onPick(target)} label={label} hint={hint} />
  );

  return (
    <div
      className="fixed inset-0 z-[70] flex items-end justify-center sm:items-center"
      style={{ background: "rgba(0, 0, 0, 0.35)" }}
      onClick={(event) => {
        event.stopPropagation();
        onClose();
      }}
    >
      <div
        ref={trapRef}
        role="dialog"
        aria-modal="true"
        aria-label={t("composeWhere")}
        className="flex max-h-[85vh] w-full max-w-md flex-col gap-4 overflow-y-auto rounded-t-3xl p-5 sm:rounded-3xl"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", paddingBottom: "calc(1.25rem + env(safe-area-inset-bottom))" }}
        onClick={(event) => event.stopPropagation()}
      >
        <h2 className="text-lg font-extrabold" style={{ color: "var(--text)" }}>{t("composeWhere")}</h2>
        {groups.map(({ club, channels, publicChannel }) => (
          <fieldset key={club.id} className="flex flex-col gap-2">
            <legend className="mb-1 text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
              {club.name}
            </legend>
            {channels.map((channel) =>
              option(
                { kind: "channel", channelId: channel.id, public: false },
                `#${channelName(channel, t)}`,
                t("composeAudienceHint"),
                channel.id,
              ),
            )}
            {publicChannel
              ? option(
                  { kind: "channel", channelId: publicChannel.id, public: true },
                  t("audienceBoxPublic", { club: club.name }),
                  t("audienceBoxPublicHint"),
                  `${publicChannel.id}:public`,
                )
              : null}
          </fieldset>
        ))}
        <fieldset className="flex flex-col gap-2">
          <legend className="mb-1 text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {t("audienceProfile")}
          </legend>
          {option({ kind: "profile", audience: "followers" }, t("audienceFollowers"), t("audienceFollowersHint"), "followers")}
          {option({ kind: "profile", audience: "public" }, t("audiencePublic"), t("audiencePublicHint"), "public")}
        </fieldset>
      </div>
    </div>
  );
}

function entryLabel(item: TypedJournalItem, t: (key: string) => string): string {
  switch (item.kind) {
    case "execution":
      return item.entry.workout_title ?? t("attachmentWorkout");
    case "training_log":
      return item.entry.title ?? t("attachmentWorkout");
    case "pr":
      return `${item.entry.name} · ${formatScore(Number(item.entry.current_score), item.entry.unit)}`;
    default:
      return t("attachmentWorkout");
  }
}

function Choice({
  name,
  checked,
  onChange,
  label,
  hint,
}: {
  name: string;
  checked: boolean;
  onChange: () => void;
  label: string;
  hint?: string;
}) {
  return (
    <label className="flex min-h-11 cursor-pointer items-center gap-3 rounded-2xl px-3 py-2" style={{ border: "1px solid var(--border)" }}>
      <input type="radio" name={name} checked={checked} onChange={onChange} />
      <span className="flex min-w-0 flex-col">
        <span className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{label}</span>
        {hint ? <span className="text-xs" style={{ color: "var(--dim)" }}>{hint}</span> : null}
      </span>
    </label>
  );
}
