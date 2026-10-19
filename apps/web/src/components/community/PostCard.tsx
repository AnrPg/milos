"use client";

import Link from "next/link";
import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  addComment,
  deleteComment,
  deletePost,
  FEED_KEY,
  fetchComments,
  setKudos,
  setPostHidden,
  setPostPinned,
  type CommunityPost,
} from "@/api/community";
import { SOCIAL_KEY } from "@/api/social";
import { clientErrorMessage } from "@/components/client/errors";
import { formatDateTime } from "@/components/client/format";
import { channelName, clubInitials } from "@/components/community/community";
import { formatScore } from "@/components/pantheon/PantheonCard";
import { SemanticLabel } from "@/components/semantic-label";
import { useSession } from "@/components/session-provider";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import type { PRRecord } from "@/api/gamification";

/**
 * One post (vision §7.1): its origin (`Club › #channel`) on top, then the
 * author, text, the shared journal entry, kudos and comments. Staff hide,
 * delete and pin; authors delete their own (D8).
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
  const author = post.author.nickname ?? "?";

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
        <div className="min-w-0">
          <Link href={`/people/${post.author.id}`} className="block truncate font-bold" style={{ color: "var(--text)" }}>
            {author}
          </Link>
          <p className="text-xs" style={{ color: "var(--dim)" }}>
            <time dateTime={post.inserted_at}>{formatDateTime(post.inserted_at, locale)}</time>
          </p>
        </div>
      </header>

      {post.hidden ? (
        <p className="text-xs font-semibold" style={{ color: "var(--warning, #b45309)" }}>{t("hiddenNotice")}</p>
      ) : null}
      {post.body ? (
        <p className="whitespace-pre-wrap text-sm" style={{ color: "var(--text)" }}>{post.body}</p>
      ) : null}
      {post.attachment_type && post.attachment ? (
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
      </div>
      {error ? <p role="alert" className="text-sm" style={{ color: "var(--danger, #dc2626)" }}>{error}</p> : null}
      {showComments ? <Comments post={post} /> : null}
    </article>
  );
}

/** `Club › #channel`, the box alone for its public post, or the audience of a profile post. */
function origin(post: CommunityPost, t: ReturnType<typeof useTranslations>) {
  if (post.origin === "profile" || !post.club) {
    return post.audience === "public" ? t("audiencePublic") : t("audienceFollowers");
  }
  return post.channel ? `${post.club.name} › #${channelName(post.channel, t)}` : post.club.name;
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

function Attachment({ type, snapshot }: { type: string; snapshot: Snapshot }) {
  const t = useTranslations("Community");
  const title = typeof snapshot.title === "string" ? snapshot.title : t("attachmentWorkout");
  let detail: React.ReactNode = null;

  if (type === "pr" && typeof snapshot.score === "number" && typeof snapshot.unit === "string") {
    detail = (
      <>
        <span className="tabular-nums">{formatScore(snapshot.score, snapshot.unit as PRRecord["unit"])}</span>{" "}
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
          <li key={comment.id} className="text-sm" style={{ color: "var(--text)" }}>
            <b>{comment.author.nickname ?? "?"}</b> <span className="whitespace-pre-wrap">{comment.body}</span>
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
      {error ? <p role="alert" className="text-sm" style={{ color: "var(--danger, #dc2626)" }}>{error}</p> : null}
    </div>
  );
}
