"use client";

import { useCallback, useEffect, useRef, useState } from "react";

import { requestBodyPhotoUpload, type BodyPhotoUploadRequest, type BodyPose } from "@/api/body";
import { discardMedia } from "@/api/media";
import { contentTypeOf } from "@/lib/post-media";
import { putPresigned } from "@/lib/presigned-upload";

export type PendingPhoto = {
  pose: BodyPose;
  previewUrl: string;
  mediaId: string | null;
  phase: "uploading" | "ready" | "failed";
  error?: unknown;
};

export const BODY_PHOTO_TYPES = ["image/heic", "image/heif", "image/jpeg", "image/png", "image/webp"];

/**
 * Body photos picked on the Μέτρηση form (ADR-158 §4): each goes straight
 * to private storage through the presigned upload as soon as it is kept,
 * and is attached to the snapshot on save. Replacing or removing one gives
 * the upload back.
 */
export function useBodyPhotoUploads(token: string | null, limits?: { content_types: string[]; max_bytes: number }) {
  const [pending, setPending] = useState<Partial<Record<BodyPose, PendingPhoto>>>({});
  const pendingRef = useRef(pending);
  const controllers = useRef(new Map<BodyPose, AbortController>());

  const commit = useCallback((update: (current: Partial<Record<BodyPose, PendingPhoto>>) => Partial<Record<BodyPose, PendingPhoto>>) => {
    pendingRef.current = update(pendingRef.current);
    setPending(pendingRef.current);
  }, []);

  const release = useCallback(
    (pose: BodyPose, giveBack = true) => {
      controllers.current.get(pose)?.abort();
      controllers.current.delete(pose);
      const item = pendingRef.current[pose];
      if (!item) return;
      URL.revokeObjectURL(item.previewUrl);
      if (giveBack && item.mediaId && token) void discardMedia(token, item.mediaId).catch(() => undefined);
      commit((current) => {
        const next = { ...current };
        delete next[pose];
        return next;
      });
    },
    [commit, token],
  );

  const add = useCallback(
    async (pose: BodyPose, blob: Blob) => {
      if (!token) return;
      release(pose);
      const controller = new AbortController();
      controllers.current.set(pose, controller);
      const previewUrl = URL.createObjectURL(blob);
      const contentType = contentTypeOf({ type: blob.type, name: blob instanceof File ? blob.name : "photo.jpg" }) || "image/jpeg";
      commit((current) => ({ ...current, [pose]: { pose, previewUrl, mediaId: null, phase: "uploading" } }));
      const fail = (error: unknown) =>
        commit((current) => (current[pose]?.previewUrl === previewUrl ? { ...current, [pose]: { ...current[pose]!, phase: "failed", error } } : current));
      const allowed = limits?.content_types ?? BODY_PHOTO_TYPES;
      if (!allowed.includes(contentType)) return fail("unsupported");
      if (limits && blob.size > limits.max_bytes) return fail("tooLarge");
      try {
        const upload = await requestBodyPhotoUpload(
          token,
          { content_type: contentType as BodyPhotoUploadRequest["content_type"], byte_size: blob.size },
          controller.signal,
        );
        commit((current) => (current[pose]?.previewUrl === previewUrl ? { ...current, [pose]: { ...current[pose]!, mediaId: upload.media_id } } : current));
        await putPresigned(upload.upload_url, blob, upload.required_headers, { signal: controller.signal });
        commit((current) => (current[pose]?.previewUrl === previewUrl ? { ...current, [pose]: { ...current[pose]!, phase: "ready" } } : current));
      } catch (caught) {
        if (controller.signal.aborted) return;
        fail(caught);
      } finally {
        if (controllers.current.get(pose) === controller) controllers.current.delete(pose);
      }
    },
    [commit, limits, release, token],
  );

  /** After save: forget the uploads without giving them back (they are attached now). */
  const settle = useCallback(() => {
    for (const item of Object.values(pendingRef.current)) if (item) URL.revokeObjectURL(item.previewUrl);
    commit(() => ({}));
  }, [commit]);

  useEffect(() => {
    const live = controllers.current;
    return () => live.forEach((controller) => controller.abort());
  }, []);

  const items = Object.values(pending).filter((item): item is PendingPhoto => Boolean(item));
  return {
    pending,
    add,
    remove: release,
    settle,
    busy: items.some((item) => item.phase === "uploading"),
    failed: items.some((item) => item.phase === "failed"),
    ready: items.filter((item) => item.phase === "ready" && item.mediaId) as (PendingPhoto & { mediaId: string })[],
  };
}
