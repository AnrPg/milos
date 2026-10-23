"use client";

import { useCallback, useEffect, useRef, useState } from "react";

import type { ShopMedia } from "@/api/shop";
import { completeMediaUpload, discardMedia, requestMediaUpload, type MediaContentType } from "@/api/media";
import { useSession } from "@/components/session-provider";
import { preparePhoto } from "@/lib/media-files";
import { putPresigned } from "@/lib/presigned-upload";

export type ProductPhoto = {
  key: string;
  mediaId: string | null;
  previewUrl: string | null;
  state: "uploading" | "ready" | "failed";
};

/** Product photos go square; the list shows the first one. */
export const MAX_PRODUCT_PHOTOS = 6;

let sequence = 0;

/**
 * Product photos through the shared media upload (ADR-157): crop to a
 * square, reserve, PUT to storage, complete. TODO(ADR-190): the purpose is
 * `post_photo` until the media API takes a `shop_product_photo` purpose.
 */
export function useProductPhotos(initial: ShopMedia[] | undefined) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const [photos, setPhotos] = useState<ProductPhoto[]>([]);
  const seeded = useRef(false);
  const added = useRef<string[]>([]);

  useEffect(() => {
    if (seeded.current || !initial) return;
    seeded.current = true;
    queueMicrotask(() =>
      setPhotos(initial.map((media) => ({ key: media.id, mediaId: media.id, previewUrl: media.thumb_url ?? media.full_url ?? null, state: "ready" }))),
    );
  }, [initial]);

  const patch = useCallback((key: string, change: Partial<ProductPhoto>) => {
    setPhotos((current) => current.map((photo) => (photo.key === key ? { ...photo, ...change } : photo)));
  }, []);

  const upload = useCallback(
    async (key: string, file: File) => {
      if (!token) return;
      try {
        const prepared = await preparePhoto(file, "1:1");
        patch(key, { previewUrl: URL.createObjectURL(prepared.blob) });
        const reserved = await requestMediaUpload(token, {
          purpose: "post_photo",
          content_type: prepared.contentType as MediaContentType,
          byte_size: prepared.blob.size,
        });
        patch(key, { mediaId: reserved.media_id });
        added.current.push(reserved.media_id);
        await putPresigned(reserved.upload_url, prepared.blob, reserved.required_headers);
        await completeMediaUpload(token, reserved.media_id);
        patch(key, { state: "ready" });
      } catch {
        patch(key, { state: "failed" });
      }
    },
    [patch, token],
  );

  const add = useCallback(
    (files: File[]) => {
      const room = Math.max(MAX_PRODUCT_PHOTOS - photos.length, 0);
      const fresh = files.slice(0, room).map((file) => {
        sequence += 1;
        return { file, photo: { key: `photo-${sequence}`, mediaId: null, previewUrl: null, state: "uploading" as const } };
      });
      setPhotos((current) => [...current, ...fresh.map((entry) => entry.photo)]);
      for (const entry of fresh) void upload(entry.photo.key, entry.file);
    },
    [photos.length, upload],
  );

  const remove = useCallback(
    (key: string) => {
      setPhotos((current) => {
        const photo = current.find((entry) => entry.key === key);
        // Only an upload made here is given back; a saved photo leaves with the product's next save.
        if (photo?.mediaId && token && added.current.includes(photo.mediaId)) void discardMedia(token, photo.mediaId).catch(() => undefined);
        return current.filter((entry) => entry.key !== key);
      });
    },
    [token],
  );

  const makeFirst = useCallback((key: string) => {
    setPhotos((current) => {
      const photo = current.find((entry) => entry.key === key);
      return photo ? [photo, ...current.filter((entry) => entry.key !== key)] : current;
    });
  }, []);

  return {
    photos,
    add,
    remove,
    makeFirst,
    busy: photos.some((photo) => photo.state === "uploading"),
    mediaIds: photos.filter((photo) => photo.state === "ready" && photo.mediaId).map((photo) => photo.mediaId!),
  };
}
