"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useId, useState } from "react";

import {
  archiveAdminVideo,
  createAdminVideo,
  fetchAdminVideos,
  setAdminVideoPublished,
  updateAdminVideo,
  type ContentVideo,
} from "@/api/admin-content";
import { useSession } from "@/components/session-provider";
import { isHttpsUrl, optionalInt, parseTags, staffErrorMessage, videoState, type VideoState } from "@/components/staff/staff-helpers";
import {
  dangerButtonStyle,
  inputClass,
  inputStyle,
  captionClass,
  captionStyle,
  Pill,
  primaryButtonClass,
  primaryButtonStyle,
  secondaryButtonClass,
  secondaryButtonStyle,
  StaffPanel,
  StatusText,
} from "@/components/staff/staff-ui";
import { PageHeader } from "@/components/PageHeader";
import { useUiTranslations } from "@/i18n/ui";
import { Select } from "@/components/ui/Select";

const VIDEOS_KEY = ["admin", "videos"] as const;
type Filter = "all" | VideoState;

function VideoForm({ video, onDone }: { video: ContentVideo | null; onDone: () => void }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const baseId = useId();
  const [title, setTitle] = useState(video?.title ?? "");
  const [description, setDescription] = useState(video?.description ?? "");
  const [url, setUrl] = useState(video?.video_url ?? "");
  const [duration, setDuration] = useState(video?.duration_minutes ? String(video.duration_minutes) : "");
  const [tags, setTags] = useState((video?.tags ?? []).join(", "));

  const durationValue = optionalInt(duration);
  const durationValid = durationValue === null || (Number.isFinite(durationValue) && durationValue >= 1 && durationValue <= 600);
  const urlValid = isHttpsUrl(url);
  const valid = title.trim().length >= 2 && urlValid && durationValid;

  const mutation = useMutation({
    mutationFn: () => {
      const body = {
        title: title.trim(),
        description: description.trim() || null,
        video_url: url.trim(),
        duration_minutes: durationValue,
        tags: parseTags(tags),
      };
      return video ? updateAdminVideo(tokens!.access_token, video.id, body) : createAdminVideo(tokens!.access_token, body);
    },
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: VIDEOS_KEY });
      onDone();
    },
  });

  return (
    <form
      className="grid gap-3 sm:grid-cols-2"
      onSubmit={(event) => {
        event.preventDefault();
        if (valid) mutation.mutate();
      }}
    >
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-title`} style={captionStyle}>
          {i18n("title768e0c1")}
        </label>
        <input
          id={`${baseId}-title`}
          className={inputClass}
          maxLength={120}
          onChange={(event) => setTitle(event.target.value)}
          required
          style={inputStyle}
          value={title}
        />
      </div>
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-url`} style={captionStyle}>
          {i18n("stfVideoUrl")}
        </label>
        <input
          id={`${baseId}-url`}
          aria-describedby={`${baseId}-url-hint`}
          aria-invalid={url.length > 0 && !urlValid}
          className={inputClass}
          inputMode="url"
          maxLength={2000}
          onChange={(event) => setUrl(event.target.value)}
          placeholder="https://"
          required
          style={inputStyle}
          type="url"
          value={url}
        />
        <p id={`${baseId}-url-hint`} className="text-xs" style={{ color: url.length > 0 && !urlValid ? "var(--danger)" : "var(--dim)" }}>
          {i18n("stfVideoUrlHint")}
        </p>
      </div>
      <div className="space-y-1 sm:col-span-2">
        <label className={captionClass} htmlFor={`${baseId}-description`} style={captionStyle}>
          {i18n("description55f8ebc")}
        </label>
        <textarea
          id={`${baseId}-description`}
          className={`${inputClass} min-h-24`}
          maxLength={2000}
          onChange={(event) => setDescription(event.target.value)}
          style={inputStyle}
          value={description}
        />
      </div>
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-duration`} style={captionStyle}>
          {i18n("durationMinutesLabel")}
        </label>
        <input
          id={`${baseId}-duration`}
          className={inputClass}
          inputMode="numeric"
          max={600}
          min={1}
          onChange={(event) => setDuration(event.target.value)}
          style={inputStyle}
          type="number"
          value={duration}
        />
      </div>
      <div className="space-y-1">
        <label className={captionClass} htmlFor={`${baseId}-tags`} style={captionStyle}>
          {i18n("tagsCommaSeparated7bfd75e")}
        </label>
        <input
          id={`${baseId}-tags`}
          className={inputClass}
          onChange={(event) => setTags(event.target.value)}
          style={inputStyle}
          value={tags}
        />
      </div>
      <div className="flex flex-wrap items-center gap-3 sm:col-span-2">
        <button className={primaryButtonClass} disabled={!valid || mutation.isPending} style={primaryButtonStyle} type="submit">
          {mutation.isPending ? i18n("stfSaving") : video ? i18n("saveChanges179359b") : i18n("stfAddVideo")}
        </button>
        <button className={secondaryButtonClass} onClick={onDone} style={secondaryButtonStyle} type="button">
          {i18n("cancel77dfd21")}
        </button>
        {mutation.isError ? <StatusText tone="error">{staffErrorMessage(mutation.error, i18n)}</StatusText> : null}
      </div>
    </form>
  );
}

function VideoRow({ video, onEdit }: { video: ContentVideo; onEdit: () => void }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const state = videoState(video);
  const refresh = () => queryClient.invalidateQueries({ queryKey: VIDEOS_KEY });

  const publish = useMutation({
    mutationFn: (published: boolean) => setAdminVideoPublished(token, video.id, published),
    onSuccess: refresh,
  });
  const archive = useMutation({ mutationFn: () => archiveAdminVideo(token, video.id), onSuccess: refresh });
  const error = publish.error ?? archive.error;

  return (
    <li className="rounded-[1.4rem] p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {video.title}
          </p>
          <p className="mt-0.5 text-xs" style={{ color: "var(--dim)" }}>
            {[video.duration_minutes ? i18n("stfMinutes", { count: video.duration_minutes }) : null, video.tags.join(", ")]
              .filter(Boolean)
              .join(" · ")}
          </p>
          {video.description ? (
            <p className="mt-1 line-clamp-2 text-sm" data-user-text style={{ color: "var(--muted)" }}>
              {video.description}
            </p>
          ) : null}
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {state === "published" ? (
            <Pill tone="spark">{i18n("stfVideoPublished")}</Pill>
          ) : state === "archived" ? (
            <Pill tone="neutral">{i18n("stfVideoArchived")}</Pill>
          ) : (
            <Pill tone="warning">{i18n("stfVideoDraft")}</Pill>
          )}
          <a
            className={secondaryButtonClass}
            href={video.video_url}
            rel="noopener noreferrer"
            style={secondaryButtonStyle}
            target="_blank"
          >
            {i18n("stfOpenVideo")}
          </a>
          {state !== "archived" ? (
            <>
              <button className={secondaryButtonClass} onClick={onEdit} style={secondaryButtonStyle} type="button">
                {i18n("edit5301648")}
              </button>
              <button
                className={secondaryButtonClass}
                disabled={publish.isPending}
                onClick={() => publish.mutate(state !== "published")}
                style={secondaryButtonStyle}
                type="button"
              >
                {state === "published" ? i18n("stfUnpublish") : i18n("publish5656400")}
              </button>
              <button
                className={secondaryButtonClass}
                disabled={archive.isPending}
                onClick={() => {
                  if (window.confirm(i18n("stfArchiveVideoConfirm", { title: video.title }))) archive.mutate();
                }}
                style={dangerButtonStyle}
                type="button"
              >
                {i18n("stfArchive")}
              </button>
            </>
          ) : null}
        </div>
      </div>
      {error ? (
        <div className="mt-2">
          <StatusText tone="error">{staffErrorMessage(error, i18n)}</StatusText>
        </div>
      ) : null}
    </li>
  );
}

export function AdminContent() {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const [editing, setEditing] = useState<ContentVideo | "new" | null>(null);
  const [filter, setFilter] = useState<Filter>("all");
  const filterId = useId();

  const videosQuery = useQuery({
    queryKey: VIDEOS_KEY,
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchAdminVideos(tokens!.access_token),
  });

  const videos = (videosQuery.data ?? []).filter((video) => filter === "all" || videoState(video) === filter);

  return (
    <main className="min-h-screen px-4 py-10 sm:px-6 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-5xl space-y-6">
        <PageHeader title={i18n("stfContentTitle")} />

        {editing ? (
          <StaffPanel labelledBy="content-video-form" title={editing === "new" ? i18n("stfAddVideo") : i18n("stfEditVideo")}>
            <VideoForm
              key={editing === "new" ? "new" : editing.id}
              onDone={() => setEditing(null)}
              video={editing === "new" ? null : editing}
            />
          </StaffPanel>
        ) : null}

        <StaffPanel
          labelledBy="content-videos"
          title={i18n("stfVideosTitle")}
          actions={
            <>
              <label className="sr-only" htmlFor={filterId}>
                {i18n("statusbae7d5b")}
              </label>
              <Select
                id={filterId}
                className="rounded-xl px-3 py-1.5 text-sm"
                onValueChange={(value) => setFilter(value as Filter)}
                style={inputStyle}
                value={filter}
              >
                <option value="all">{i18n("all6a72085")}</option>
                <option value="draft">{i18n("stfVideoDraft")}</option>
                <option value="published">{i18n("stfVideoPublished")}</option>
                <option value="archived">{i18n("stfVideoArchived")}</option>
              </Select>
              {editing === null ? (
                <button className={primaryButtonClass} onClick={() => setEditing("new")} style={primaryButtonStyle} type="button">
                  {i18n("stfAddVideo")}
                </button>
              ) : null}
            </>
          }
        >
          {videosQuery.isPending ? (
            <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
          ) : videosQuery.isError ? (
            <StatusText tone="error">{staffErrorMessage(videosQuery.error, i18n)}</StatusText>
          ) : videos.length === 0 ? (
            <StatusText tone="muted">{i18n("stfNoVideos")}</StatusText>
          ) : (
            <ul className="space-y-3">
              {videos.map((video) => (
                <VideoRow key={video.id} onEdit={() => setEditing(video)} video={video} />
              ))}
            </ul>
          )}
        </StaffPanel>
      </div>
    </main>
  );
}
