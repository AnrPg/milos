"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";

import { fetchMyVideos, type OnDemandVideo } from "@/api/content";
import { useSession } from "@/components/session-provider";
import { ClientPage, EmptyLine, LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { FeatureGate } from "@/components/client/FeatureGate";
import { filterVideosByTag, safeVideoUrl, videoHost, videoTags } from "@/components/client/video";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useUiTranslations } from "@/i18n/ui";

/** `/box/videos`: published on-demand videos (needs `watch_on_demand`). */
export function VideosConsole() {
  const i18n = useUiTranslations();
  return (
    <ClientPage title={i18n("clVideosTitle")} intro={i18n("clVideosIntro")}>
      <FeatureGate feature="videos">
        <VideoLibrary />
      </FeatureGate>
    </ClientPage>
  );
}

function VideoLibrary() {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const [tag, setTag] = useState<string | null>(null);
  const query = useQuery({
    queryKey: ["me", "videos"],
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchMyVideos(tokens!.access_token),
  });
  const videos = useMemo(() => query.data ?? [], [query.data]);
  const tags = useMemo(() => videoTags(videos, locale), [videos, locale]);
  const visible = useMemo(() => filterVideosByTag(videos, tag), [videos, tag]);

  if (query.isPending) return <LoadingLine />;
  if (query.isError) return <QueryProblem error={query.error} onRetry={() => void query.refetch()} />;
  if (videos.length === 0) return <EmptyLine>{i18n("clVideosEmpty")}</EmptyLine>;

  return (
    <div className="flex flex-col gap-4">
      {tags.length > 0 ? (
        <div role="group" aria-label={i18n("clVideosFilterLabel")} className="flex flex-wrap gap-2">
          {[null, ...tags].map((value) => {
            const active = tag === value;
            return (
              <button
                key={value ?? "__all"}
                type="button"
                aria-pressed={active}
                onClick={() => setTag(value)}
                className="rounded-full px-3 py-1 text-xs font-semibold"
                style={{
                  background: active ? "var(--primary)" : "var(--border)",
                  color: active ? "var(--primary-contrast)" : "var(--text-soft)",
                }}
              >
                {value ?? i18n("all6a72085")}
              </button>
            );
          })}
        </div>
      ) : null}

      {visible.length === 0 ? (
        <EmptyLine>{i18n("clVideosNoMatch")}</EmptyLine>
      ) : (
        <ul className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {visible.map((video) => (
            <VideoCard key={video.id} video={video} />
          ))}
        </ul>
      )}
    </div>
  );
}

function VideoCard({ video }: { video: OnDemandVideo }) {
  const i18n = useUiTranslations();
  const url = safeVideoUrl(video.video_url);
  const host = videoHost(video.video_url);

  return (
    <li
      className="flex flex-col gap-2 rounded-2xl p-4"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div className="flex items-start justify-between gap-2">
        <h2 className="break-words text-base font-semibold" style={{ color: "var(--text)" }}>
          {video.title}
        </h2>
        {video.duration_minutes ? (
          <span className="shrink-0 rounded-full px-2 py-0.5 text-[11px] font-semibold tabular-nums" style={{ background: "var(--panel-muted)", color: "var(--dim)" }}>
            {i18n("clMinutesShort", { count: video.duration_minutes })}
          </span>
        ) : null}
      </div>
      {video.description ? (
        <p className="line-clamp-4 whitespace-pre-line text-sm" style={{ color: "var(--muted)" }}>
          {video.description}
        </p>
      ) : null}
      {video.tags.length > 0 ? (
        <ul className="flex flex-wrap gap-1" aria-label={i18n("tags848eed0")}>
          {video.tags.map((value) => (
            <li key={value} className="rounded-full px-2 py-0.5 text-[11px]" style={{ background: "var(--panel-muted)", color: "var(--dim)" }}>
              {value}
            </li>
          ))}
        </ul>
      ) : null}
      <div className="mt-auto pt-2">
        {url ? (
          <a
            href={url}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1 rounded-full px-4 py-2 text-sm font-semibold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            aria-label={`${i18n("clVideoWatch")}: ${video.title} (${i18n("clVideoOpensNewTab", { host: host ?? "" })})`}
          >
            {i18n("clVideoWatch")}
            <span aria-hidden="true">↗</span>
          </a>
        ) : (
          <span className="text-xs" style={{ color: "var(--dim)" }}>
            {i18n("clVideoUnavailable")}
          </span>
        )}
        {host ? (
          <span className="ms-2 text-xs" style={{ color: "var(--dim)" }}>
            {host}
          </span>
        ) : null}
      </div>
    </li>
  );
}
