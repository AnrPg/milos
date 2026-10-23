"use client";

import { useRef, useState } from "react";
import { useTranslations } from "next-intl";

import { Field, inputStyle } from "@/components/community/ProposeGroupSheet";
import { ErrorLine } from "@/components/community/Sheet";
import { SmallButton } from "@/components/community/GroupPage";
import { useSession } from "@/components/session-provider";
import { BoxPhotoUploadError, uploadBoxPhoto } from "@/lib/box-photo-upload";

import { useEventError } from "../EventParts";
import { fieldClass } from "./fields";
import type { StepProps } from "./types";

/** Step 2: the title, a cover (when the box takes photos) and a description. */
export function BasicsStep({
  form,
  set,
  coverSlug,
  coverUrl,
  onCover,
  onUploading,
}: StepProps & {
  coverSlug: string | null;
  coverUrl: string | null;
  onCover: (mediaId: string | null, url: string | null) => void;
  onUploading: (uploading: boolean) => void;
}) {
  const t = useTranslations("Events");
  const eventError = useEventError();
  const { tokens } = useSession();
  const fileInput = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);

  async function pick(file: File | undefined) {
    if (!file || !coverSlug || !tokens?.access_token) return;
    setUploading(true);
    onUploading(true);
    setUploadError(null);
    try {
      const media = await uploadBoxPhoto(tokens.access_token, file, coverSlug);
      onCover(media.id, media.url ?? null);
    } catch (caught) {
      setUploadError(caught instanceof BoxPhotoUploadError ? t(["upload", caught.reason].join("_")) : eventError(caught));
    } finally {
      setUploading(false);
      onUploading(false);
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <Field label={t("fieldTitle")}>
        <input
          value={form.title}
          maxLength={120}
          aria-required
          onChange={(event) => set({ title: event.target.value })}
          placeholder={t("fieldTitlePlaceholder")}
          className={fieldClass}
          style={inputStyle}
        />
      </Field>

      {coverSlug ? (
        <div className="flex flex-col gap-2">
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("fieldCover")}</p>
          {coverUrl ? (
            // eslint-disable-next-line @next/next/no-img-element -- gym-uploaded media origin
            <img src={coverUrl} alt="" className="aspect-[16/6] w-full rounded-2xl object-cover" />
          ) : null}
          <div className="flex flex-wrap gap-2">
            <SmallButton disabled={uploading} onClick={() => fileInput.current?.click()}>
              {uploading ? t("uploading") : coverUrl || form.coverMediaId ? t("coverChange") : t("coverAdd")}
            </SmallButton>
            {form.coverMediaId ? <SmallButton onClick={() => onCover(null, null)}>{t("coverRemove")}</SmallButton> : null}
          </div>
          <input ref={fileInput} type="file" accept="image/*" className="sr-only" aria-label={t("coverAdd")} onChange={(event) => void pick(event.target.files?.[0])} />
          <ErrorLine message={uploadError} />
        </div>
      ) : null}

      <Field label={t("fieldDescription")}>
        <textarea
          value={form.description}
          maxLength={2000}
          rows={4}
          onChange={(event) => set({ description: event.target.value })}
          placeholder={t("fieldDescriptionPlaceholder")}
          className="w-full rounded-2xl px-3 py-2 text-sm font-normal"
          style={inputStyle}
        />
      </Field>
    </div>
  );
}
