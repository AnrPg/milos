"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";

import { ApiError } from "@/api/client";
import {
  MEDIA_CAPABILITIES_KEY,
  completeMediaUpload,
  discardMedia,
  fetchMedia,
  fetchMediaCapabilities,
  requestMediaUpload,
  type MediaContentType,
} from "@/api/media";
import { useSession } from "@/components/session-provider";
import { preparePhoto, readVideoDuration } from "@/lib/media-files";
import {
  DEFAULT_MEDIA_LIMITS,
  INITIAL_UPLOAD,
  admitFiles,
  contentTypeOf,
  isBusy,
  isPermanent,
  isPublishable,
  moveItem,
  pollDelay,
  uploadErrorOf,
  uploadReducer,
  type CompositionRefusal,
  type CropAspect,
  type MediaKind,
  type MediaLimits,
  type UploadError,
  type UploadEvent,
  type UploadState,
} from "@/lib/post-media";
import { PresignedUploadError, putPresigned } from "@/lib/presigned-upload";

/** One picked file in compose, from picking to processed. */
export type ComposeMediaItem = {
  key: string;
  file: File;
  kind: MediaKind;
  /** An object URL of what is being uploaded (the cropped photo, or the video). */
  previewUrl: string;
  aspect: CropAspect;
  /** False when the browser cannot decode the photo (HEIC): it goes uncropped. */
  croppable: boolean;
  upload: UploadState;
  mediaId: string | null;
  altText: string;
};

/** Polls stop after this many tries; the post may still publish and finish later. */
const MAX_POLLS = 80;

class Aborted extends Error {}

function sleep(ms: number, signal: AbortSignal) {
  return new Promise<void>((resolve, reject) => {
    if (signal.aborted) return reject(new Aborted());
    const timer = window.setTimeout(resolve, ms);
    signal.addEventListener(
      "abort",
      () => {
        window.clearTimeout(timer);
        reject(new Aborted());
      },
      { once: true },
    );
  });
}

function errorOf(caught: unknown): UploadError {
  if (caught instanceof ApiError) return uploadErrorOf(caught.payload.code, caught.status);
  if (caught instanceof PresignedUploadError) {
    if (caught.reason === "network") return typeof navigator !== "undefined" && !navigator.onLine ? "offline" : "network";
    return "storage";
  }
  if (typeof navigator !== "undefined" && !navigator.onLine) return "offline";
  return caught instanceof TypeError ? "network" : "unknown";
}

function isAbort(caught: unknown) {
  return (
    caught instanceof Aborted ||
    (caught instanceof PresignedUploadError && caught.reason === "aborted") ||
    (caught instanceof DOMException && caught.name === "AbortError")
  );
}

let sequence = 0;
const nextKey = () => {
  sequence += 1;
  return ["media", Date.now().toString(36), String(sequence)].join("-");
};

/**
 * Compose's photos and video (ADR-157). Each file starts uploading as soon as
 * it is picked: prepare (resize a photo, measure a video) → reserve → PUT with
 * progress → complete → poll until processed. Removing, re-cropping or closing
 * aborts what is in flight and gives back the upload.
 */
export function useComposeMedia() {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const tokenRef = useRef(token);
  const capabilities = useQuery({
    queryKey: MEDIA_CAPABILITIES_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchMediaCapabilities(token!),
    staleTime: 10 * 60_000,
  });
  const limits: MediaLimits = capabilities.data ?? DEFAULT_MEDIA_LIMITS;
  const limitsRef = useRef(limits);
  const [items, setItems] = useState<ComposeMediaItem[]>([]);
  const itemsRef = useRef(items);
  const [refusal, setRefusal] = useState<CompositionRefusal | null>(null);
  const controllers = useRef(new Map<string, AbortController>());

  useEffect(() => {
    tokenRef.current = token;
    limitsRef.current = limits;
  });

  const commit = useCallback((update: (current: ComposeMediaItem[]) => ComposeMediaItem[]) => {
    itemsRef.current = update(itemsRef.current);
    setItems(itemsRef.current);
  }, []);

  const patch = useCallback(
    (key: string, change: Partial<ComposeMediaItem> | ((item: ComposeMediaItem) => Partial<ComposeMediaItem>)) =>
      commit((current) =>
        current.map((item) => (item.key === key ? { ...item, ...(typeof change === "function" ? change(item) : change) } : item)),
      ),
    [commit],
  );

  const send = useCallback(
    (key: string, event: UploadEvent) => patch(key, (item) => ({ upload: uploadReducer(item.upload, event) })),
    [patch],
  );

  const giveBack = useCallback((mediaId: string | null) => {
    const current = tokenRef.current;
    if (mediaId && current) void discardMedia(current, mediaId).catch(() => undefined);
  }, []);

  const run = useCallback(
    async (key: string) => {
      controllers.current.get(key)?.abort();
      const controller = new AbortController();
      controllers.current.set(key, controller);
      const { signal } = controller;
      const find = () => itemsRef.current.find((item) => item.key === key);
      const start = find();
      if (!start) return;
      const max = limitsRef.current;
      send(key, { type: "prepare" });

      try {
        let blob: Blob = start.file;
        let contentType = contentTypeOf(start.file);
        if (start.kind === "photo") {
          const prepared = await preparePhoto(start.file, start.aspect);
          if (signal.aborted) throw new Aborted();
          blob = prepared.blob;
          contentType = prepared.contentType;
          const previewUrl = URL.createObjectURL(blob);
          patch(key, (item) => {
            URL.revokeObjectURL(item.previewUrl);
            return { previewUrl, croppable: prepared.blob !== start.file };
          });
          if (blob.size > max.max_photo_bytes) return send(key, { type: "reject", error: "tooLarge" });
          if (!max.photo_content_types.includes(contentType)) return send(key, { type: "reject", error: "unsupported" });
        } else {
          if (blob.size > max.max_video_bytes) return send(key, { type: "reject", error: "tooLarge" });
          const duration = await readVideoDuration(blob);
          if (signal.aborted) throw new Aborted();
          // A little slack for container rounding; the server has the last word.
          if (duration !== null && duration > max.max_video_seconds * 1000 + 500) {
            return send(key, { type: "reject", error: "tooLong" });
          }
          if (!max.video_content_types.includes(contentType)) return send(key, { type: "reject", error: "unsupported" });
        }

        const current = tokenRef.current;
        if (!current) throw new Error("signed out");
        send(key, { type: "start" });
        const upload = await requestMediaUpload(
          current,
          {
            purpose: start.kind === "photo" ? "post_photo" : "post_video",
            content_type: contentType as MediaContentType,
            byte_size: blob.size,
          },
          signal,
        );
        patch(key, { mediaId: upload.media_id });
        let lastPercent = -1;
        await putPresigned(upload.upload_url, blob, upload.required_headers, {
          signal,
          onProgress: (loaded, total) => {
            const percent = Math.floor((loaded / Math.max(1, total)) * 100);
            if (percent === lastPercent) return;
            lastPercent = percent;
            send(key, { type: "progress", loaded, total });
          },
        });
        send(key, { type: "uploaded" });
        const completed = await completeMediaUpload(current, upload.media_id, signal);
        send(key, { type: "completed", status: completed.status });
        if (completed.alt_text) patch(key, { altText: completed.alt_text });

        for (let attempt = 0; attempt < MAX_POLLS && find()?.upload.phase === "processing"; attempt += 1) {
          await sleep(pollDelay(attempt), signal);
          const media = await fetchMedia(tokenRef.current ?? current, upload.media_id, signal).catch((caught) => {
            if (isAbort(caught)) throw caught;
            return null; // a missed poll is retried on the next tick
          });
          if (media) send(key, { type: "polled", status: media.status });
        }
      } catch (caught) {
        if (isAbort(caught) || signal.aborted) return;
        const error = errorOf(caught);
        const item = find();
        if (item?.upload.phase === "completing" && caught instanceof ApiError && caught.status === 422) {
          // The server looked at the bytes and refused them (it already deleted the upload).
          patch(key, { mediaId: null });
          return send(key, { type: "reject", error });
        }
        send(key, isPermanent(error) ? { type: "reject", error } : { type: "fail", error });
      } finally {
        if (controllers.current.get(key) === controller) controllers.current.delete(key);
      }
    },
    [patch, send],
  );

  const add = useCallback(
    (files: File[]) => {
      const { accepted, refusal: refused } = admitFiles(
        itemsRef.current.map((item) => item.kind),
        files,
        limitsRef.current,
      );
      setRefusal(refused);
      const fresh: ComposeMediaItem[] = accepted.map(({ file, kind }) => ({
        key: nextKey(),
        file,
        kind,
        previewUrl: URL.createObjectURL(file),
        aspect: "original",
        croppable: kind === "photo",
        upload: INITIAL_UPLOAD,
        mediaId: null,
        altText: "",
      }));
      commit((current) => [...current, ...fresh]);
      for (const item of fresh) void run(item.key);
    },
    [commit, run],
  );

  const remove = useCallback(
    (key: string) => {
      controllers.current.get(key)?.abort();
      controllers.current.delete(key);
      const item = itemsRef.current.find((entry) => entry.key === key);
      if (!item) return;
      URL.revokeObjectURL(item.previewUrl);
      if (item.upload.phase !== "rejected") giveBack(item.mediaId);
      commit((current) => current.filter((entry) => entry.key !== key));
      setRefusal(null);
    },
    [commit, giveBack],
  );

  const retry = useCallback(
    (key: string) => {
      const item = itemsRef.current.find((entry) => entry.key === key);
      if (!item || item.upload.phase !== "failed") return;
      giveBack(item.mediaId);
      patch(key, { mediaId: null });
      send(key, { type: "retry" });
      void run(key);
    },
    [giveBack, patch, run, send],
  );

  /** A new crop re-prepares the photo and uploads it again (the old upload is given back). */
  const setAspect = useCallback(
    (key: string, aspect: CropAspect) => {
      const item = itemsRef.current.find((entry) => entry.key === key);
      if (!item || item.kind !== "photo" || item.aspect === aspect) return;
      controllers.current.get(key)?.abort();
      giveBack(item.mediaId);
      patch(key, { aspect, mediaId: null, upload: INITIAL_UPLOAD });
      void run(key);
    },
    [giveBack, patch, run],
  );

  const move = useCallback((from: number, to: number) => commit((current) => moveItem(current, from, to)), [commit]);
  const setAltText = useCallback((key: string, altText: string) => patch(key, { altText }), [patch]);

  /** Stops everything in flight and frees the previews; `giveBackUploads` when compose is cancelled. */
  const release = useCallback(
    (giveBackUploads: boolean) => {
      controllers.current.forEach((controller) => controller.abort());
      controllers.current.clear();
      for (const item of itemsRef.current) {
        URL.revokeObjectURL(item.previewUrl);
        if (giveBackUploads && item.upload.phase !== "rejected") giveBack(item.mediaId);
      }
      commit(() => []);
    },
    [commit, giveBack],
  );

  // Back online: failed uploads that failed for the network start again.
  useEffect(() => {
    const resume = () => {
      for (const item of itemsRef.current) {
        if (item.upload.phase === "failed" && (item.upload.error === "offline" || item.upload.error === "network")) retry(item.key);
      }
    };
    window.addEventListener("online", resume);
    return () => window.removeEventListener("online", resume);
  }, [retry]);

  // Leaving the page mid-upload: abort and free the previews.
  useEffect(() => {
    const live = controllers.current;
    return () => {
      live.forEach((controller) => controller.abort());
      for (const item of itemsRef.current) URL.revokeObjectURL(item.previewUrl);
    };
  }, []);

  const summary = useMemo(() => {
    const kinds = items.map((item) => item.kind);
    return {
      kind: kinds[0] ?? null,
      count: items.length,
      busy: items.some((item) => isBusy(item.upload)),
      blocked: items.some((item) => !isPublishable(item.upload)),
      mediaIds: items.map((item) => item.mediaId).filter((value): value is string => Boolean(value)),
      room:
        kinds[0] === "video"
          ? 0
          : Math.max(0, limits.max_photos - kinds.length),
    };
  }, [items, limits.max_photos]);

  return {
    items,
    limits,
    capabilitiesLoaded: capabilities.isSuccess,
    refusal,
    dismissRefusal: () => setRefusal(null),
    add,
    remove,
    retry,
    setAspect,
    move,
    setAltText,
    release,
    ...summary,
  };
}

export type ComposeMedia = ReturnType<typeof useComposeMedia>;
