"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  addComment,
  deleteComment,
  deletePost,
  FEED_KEY,
  fetchComments,
  setCommentHidden,
  setKudos,
  setPostHidden,
  setPostPinned,
  type CommunityPost,
} from "@/api/community";
import { SOCIAL_KEY } from "@/api/social";
import { clientErrorMessage } from "@/components/client/errors";
import { formatDateTime } from "@/components/client/format";
import { channelName, clubInitials } from "@/components/community/community";
import { ReportButton } from "@/components/community/ReportButton";
import { ReportSheet } from "@/components/community/ReportSheet";
import { MediaViewer } from "@/components/media/MediaViewer";
import { PostMediaView } from "@/components/media/PostMediaView";
import { EventPostCard, EventSnapshotCard } from "@/components/events/EventPostCard";
import { formatScore } from "@/components/pantheon/PantheonCard";
import { SemanticLabel } from "@/components/semantic-label";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import type { PRRecord } from "@/api/gamification";
import { pollDelay } from "@/lib/post-media";

/**
 * One post (vision §7.1): its origin (`Club › #channel`) on top, then the
 * author, its photos or video (ADR-157), text, the shared journal entry,
 * kudos and comments. Staff (and a group's admins) hide, delete and pin;
 * authors delete their own (D8); anyone else reports it with the subtle flag
 * at the card's bottom corner (board 7 Q4, board 12).
 */
export function PostCard({ post }: { post: CommunityPost }) {
  const t = useTranslations("Community");
  const tUi = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const [showComments, setShowComments] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [reporting, setReporting] = useState(false);
  const [viewing, setViewing] = useState<number | null>(null);
  const author = post.author.nickname ?? "?";
  const tMedia = useTranslations("Media");
  const media = post.media ?? [];
  useProcessingRefresh(post);

  async function run(action: () => Promise<unknown>) {
    if (!token || busy) return;
    setBusy(true);
    setError(null);
    try {
      await action();
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: FEED_KEY }),
        queryClient.invalidateQueries({ queryKey: SOCIAL_KEY }),
      ]);
    } catch (caught) {
      setError(clientErrorMessage(caught, tUi));
    } finally {
      setBusy(false);
    }
  }

  return (
    <article
      className="flex flex-col gap-3 rounded-3xl p-4"
      style={{
        background: "var(--panel)",
        border: `1px solid ${post.pinned ? "color-mix(in srgb, var(--primary) 45%, transparent)" : "var(--border)"}`,
        opacity: post.hidden ? 0.7 : 1,
      }}
    >
      <p className="text-xs font-semibold" style={{ color: "var(--dim)" }}>
        {origin(post, t)}
        {post.pinned ? ` · ${t("pinned")}` : ""}
      </p>
      <header className="flex items-center gap-3">
        {post.author.avatar_url ? (
          // eslint-disable-next-line @next/next/no-img-element -- user-uploaded media origin
          <img src={post.author.avatar_url} alt="" className="h-10 w-10 shrink-0 rounded-full object-cover" />
        ) : (
          <span
            aria-hidden="true"
            className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-sm font-extrabold"
            style={{ background: "var(--panel-raised)", color: "var(--text)" }}
          >
            {clubInitials(author)}
          </span>
        )}
        <div className="min-w-0 grow">
          <Link href={`/people/${post.author.id}`} className="block truncate font-bold" style={{ color: "var(--text)" }}>
            {author}
          </Link>
          <p className="text-xs" style={{ color: "var(--dim)" }}>
            <time dateTime={post.inserted_at}>{formatDateTime(post.inserted_at, locale)}</time>
          </p>
        </div>
      </header>

      {post.hidden ? (
        <p className="text-xs font-semibold" style={{ color: "var(--warning)" }}>{t("hiddenNotice")}</p>
      ) : null}
      {post.media_status === "processing" ? (
        <p role="status" className="flex flex-wrap items-center gap-2 text-xs" style={{ color: "var(--text-soft)" }}>
          <span className="rounded-full px-2 py-0.5 font-bold" style={{ background: "var(--panel-raised)", color: "var(--text)" }}>
            {tMedia("processing")}
          </span>
          {tMedia("processingHint")}
        </p>
      ) : post.media_status === "failed" ? (
        <p role="alert" className="text-xs font-semibold" style={{ color: "var(--danger)" }}>{tMedia("failed")}</p>
      ) : null}
      {media.length > 0 ? <PostMediaView media={media} author={author} onOpen={setViewing} /> : null}
      {post.body ? (
        <p className="whitespace-pre-wrap text-sm" style={{ color: "var(--text)" }}>{post.body}</p>
      ) : null}
      {post.attachment_type === "event" ? (
        post.event ? (
          <EventPostCard event={post.event} />
        ) : post.attachment ? (
          <EventSnapshotCard snapshot={post.attachment} />
        ) : null
      ) : post.attachment_type && post.attachment ? (
        <Attachment type={post.attachment_type} snapshot={post.attachment} />
      ) : null}

      <div className="flex flex-wrap items-center gap-2">
        <button
          type="button"
          aria-pressed={post.kudos_by_me}
          disabled={busy}
          onClick={() => void run(() => setKudos(token!, post, !post.kudos_by_me))}
          className="min-h-11 rounded-full px-4 text-sm font-semibold disabled:opacity-50"
          style={{
            background: post.kudos_by_me ? "var(--primary)" : "var(--panel-raised)",
            color: post.kudos_by_me ? "var(--bg)" : "var(--text)",
            border: "1px solid var(--border)",
          }}
        >
          {t("kudos", { count: post.kudos_count })}
        </button>
        <button
          type="button"
          aria-expanded={showComments}
          onClick={() => setShowComments((open) => !open)}
          className="min-h-11 rounded-full px-4 text-sm font-semibold"
          style={{ background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" }}
        >
          {t("comments", { count: post.comment_count })}
        </button>
        <span className="grow" />
        {post.can_pin ? (
          <SmallAction disabled={busy} onClick={() => void run(() => setPostPinned(token!, post, !post.pinned))}>
            {post.pinned ? t("unpin") : t("pin")}
          </SmallAction>
        ) : null}
        {post.can_moderate ? (
          <SmallAction disabled={busy} onClick={() => void run(() => setPostHidden(token!, post, !post.hidden))}>
            {post.hidden ? t("unhide") : t("hide")}
          </SmallAction>
        ) : null}
        {post.can_delete ? (
          <SmallAction
            disabled={busy}
            onClick={() => {
              if (window.confirm(t("deleteConfirm"))) void run(() => deletePost(token!, post));
            }}
          >
            {t("delete")}
          </SmallAction>
        ) : null}
        {post.can_report ? <ReportButton label={t("report")} onClick={() => setReporting(true)} className="-me-2" /> : null}
      </div>
      {error ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{error}</p> : null}
      {showComments ? <Comments post={post} /> : null}
      {viewing !== null ? (
        <MediaViewer
          media={media}
          startIndex={viewing}
          caption={post.body}
          author={author}
          onClose={() => setViewing(null)}
          onReport={
            post.can_report
              ? () => {
                  setViewing(null);
                  setReporting(true);
                }
              : undefined
          }
        />
      ) : null}
      {reporting ? (
        <ReportSheet
          target="post"
          targetId={post.id}
          onClose={() => setReporting(false)}
          onReported={() => void queryClient.invalidateQueries({ queryKey: FEED_KEY })}
        />
      ) : null}
    </article>
  );
}

/**
 * While the author's post still processes its media, refetch the feeds with
 * a growing interval (the club topic also pushes `post_updated`; profile
 * posts have no topic the browser may join).
 */
function useProcessingRefresh(post: CommunityPost) {
  const queryClient = useQueryClient();
  const processing = post.media_status === "processing";
  useEffect(() => {
    if (!processing) return;
    let attempt = 0;
    let timer = 0;
    const tick = () => {
      timer = window.setTimeout(() => {
        void queryClient.invalidateQueries({ queryKey: FEED_KEY });
        void queryClient.invalidateQueries({ queryKey: SOCIAL_KEY });
        attempt += 1;
        if (attempt < 40) tick();
      }, pollDelay(attempt + 1));
    };
    tick();
    return () => window.clearTimeout(timer);
  }, [processing, post.id, queryClient]);
}

/** `Club › #channel`, the box alone for its public post, or the audience of a profile post. */
function origin(post: CommunityPost, t: ReturnType<typeof useTranslations>) {
  if (post.origin === "profile" || !post.club) {
    return post.audience === "public" ? t("audiencePublic") : t("audienceFollowers");
  }
  return post.channel ? `${post.club.name} › #${channelName(post.channel, t)}` : post.club.name;
}

/** ⋯ on a post or comment: a short menu of what the reader may do with it. */
export function MoreMenu({ label, items }: { label: string; items: { label: string; onSelect: () => void }[] }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="relative shrink-0">
      <button
        type="button"
        aria-label={label}
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
        className="flex h-11 w-11 items-center justify-center rounded-full text-lg font-bold"
        style={{ color: "var(--dim)" }}
      >
        ⋯
      </button>
      {open ? (
        <>
          <button type="button" aria-hidden="true" tabIndex={-1} className="fixed inset-0 z-10 cursor-default" onClick={() => setOpen(false)} />
          <ul
            role="menu"
            className="absolute right-0 z-20 mt-1 min-w-40 overflow-hidden rounded-2xl py-1 shadow-lg"
            style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
          >
            {items.map((item) => (
              <li key={item.label} role="none">
                <button
                  type="button"
                  role="menuitem"
                  onClick={() => {
                    setOpen(false);
                    item.onSelect();
                  }}
                  className="block min-h-11 w-full px-4 text-left text-sm font-semibold"
                  style={{ color: "var(--text)" }}
                >
                  {item.label}
                </button>
              </li>
            ))}
          </ul>
        </>
      ) : null}
    </div>
  );
}

function SmallAction({ onClick, disabled, children }: { onClick: () => void; disabled?: boolean; children: string }) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className="min-h-11 rounded-full px-3 text-xs font-semibold disabled:opacity-50"
      style={{ color: "var(--dim)", border: "1px solid var(--border)" }}
    >
      {children}
    </button>
  );
}

type Snapshot = Record<string, unknown>;

/** The card a shared journal entry or PR makes in a post (also compose's prefilled preview). */
export function Attachment({ type, snapshot }: { type: string; snapshot: Snapshot }) {
  const t = useTranslations("Community");
  const title = typeof snapshot.title === "string" ? snapshot.title : t("attachmentWorkout");
  let detail: React.ReactNode = null;

  const score = typeof snapshot.score === "number" ? snapshot.score : typeof snapshot.score === "string" ? Number(snapshot.score) : NaN;
  if (type === "pr" && Number.isFinite(score) && typeof snapshot.unit === "string") {
    detail = (
      <>
        <span className="tabular-nums">{formatScore(score, snapshot.unit as PRRecord["unit"])}</span>{" "}
        {snapshot.unit !== "mins_secs" ? <SemanticLabel value={snapshot.unit} /> : null}
      </>
    );
  } else {
    const parts: React.ReactNode[] = [];
    if (typeof snapshot.scale_level_slug === "string") parts.push(<SemanticLabel key="scale" value={snapshot.scale_level_slug} />);
    if (typeof snapshot.duration_seconds === "number" && snapshot.duration_seconds > 0) {
      parts.push(<span key="duration">{t("minutes", { count: Math.round(snapshot.duration_seconds / 60) })}</span>);
    }
    detail = parts.length
      ? parts.flatMap((part, index) => (index === 0 ? [part] : [<span key={`sep-${index}`}> · </span>, part]))
      : null;
  }

  return (
    <div className="rounded-2xl p-3" style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}>
      <p className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>
        {type === "pr" ? t("attachmentPr") : t("attachmentWorkout")}
      </p>
      <p className="font-bold" style={{ color: "var(--text)" }}>{title}</p>
      {detail ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{detail}</p> : null}
    </div>
  );
}

function Comments({ post }: { post: CommunityPost }) {
  const t = useTranslations("Community");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const key = ["community", "comments", post.id] as const;
  const comments = useQuery({ queryKey: key, enabled: Boolean(token), queryFn: () => fetchComments(token!, post) });
  const [draft, setDraft] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [reporting, setReporting] = useState<string | null>(null);

  async function refresh() {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: key }),
      queryClient.invalidateQueries({ queryKey: FEED_KEY }),
    ]);
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    const body = draft.trim();
    if (!token || !body) return;
    setError(null);
    try {
      await addComment(token, post, body);
      setDraft("");
      await refresh();
    } catch (caught) {
      setError(clientErrorMessage(caught, tUi));
    }
  }

  return (
    <div className="flex flex-col gap-2 border-t pt-3" style={{ borderColor: "var(--border)" }}>
      {comments.data?.length === 0 ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("noComments")}</p>
      ) : null}
      <ul className="flex flex-col gap-2">
        {(comments.data ?? []).map((comment) => (
          <li key={comment.id} className="flex items-start gap-1 text-sm" style={{ color: "var(--text)", opacity: comment.hidden ? 0.6 : 1 }}>
            <p className="min-w-0 grow">
              <b>{comment.author.nickname ?? "?"}</b> <span className="whitespace-pre-wrap">{comment.body}</span>
              {comment.hidden ? (
                <span className="ml-2 text-xs font-semibold" style={{ color: "var(--warning)" }}>{t("commentHidden")}</span>
              ) : null}
              {comment.can_moderate ? (
                <button
                  type="button"
                  className="ml-2 text-xs underline"
                  style={{ color: "var(--dim)" }}
                  onClick={() =>
                    void setCommentHidden(token!, comment.id, !comment.hidden)
                      .then(refresh)
                      .catch((caught) => setError(clientErrorMessage(caught, tUi)))
                  }
                >
                  {comment.hidden ? t("unhide") : t("hide")}
                </button>
              ) : null}
              {comment.can_delete ? (
                <button
                  type="button"
                  className="ml-2 text-xs underline"
                  style={{ color: "var(--dim)" }}
                  onClick={() =>
                    void deleteComment(token!, post, comment.id)
                      .then(refresh)
                      .catch((caught) => setError(clientErrorMessage(caught, tUi)))
                  }
                >
                  {t("delete")}
                </button>
              ) : null}
            </p>
            {comment.can_report ? <ReportButton label={t("report")} onClick={() => setReporting(comment.id)} /> : null}
          </li>
        ))}
      </ul>
      <form onSubmit={(event) => void submit(event)} className="flex gap-2">
        <label className="sr-only" htmlFor={`comment-${post.id}`}>{t("addComment")}</label>
        <input
          id={`comment-${post.id}`}
          value={draft}
          maxLength={2000}
          onChange={(event) => setDraft(event.target.value)}
          placeholder={t("addComment")}
          className="min-h-11 grow rounded-2xl px-3 text-sm"
          style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
        />
        <button
          type="submit"
          disabled={!draft.trim()}
          className="min-h-11 rounded-2xl px-4 text-sm font-bold disabled:opacity-50"
          style={{ background: "var(--primary)", color: "var(--bg)" }}
        >
          {t("send")}
        </button>
      </form>
      {error ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{error}</p> : null}
      {reporting ? (
        <ReportSheet target="comment" targetId={reporting} onClose={() => setReporting(null)} onReported={() => void refresh()} />
      ) : null}
    </div>
  );
}
