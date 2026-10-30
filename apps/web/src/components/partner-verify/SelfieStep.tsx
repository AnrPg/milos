"use client";

import { useEffect, useId, useRef, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  VERIFICATION_KEY,
  selfieUploadUrl,
  submitVerification,
  type VerificationLimits,
  type VerificationRequest,
} from "@/api/partner-verification";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { putPresigned } from "@/lib/presigned-upload";

import { errorFor, selfieContentType, selfieProblem, type SelfieProblem } from "./verify-model";
import { VerifyError, VerifyIcon, primaryButton, primaryStyle, secondaryStyle } from "./verify-ui";

/**
 * Step 4: a selfie holding the request's 4-digit code written on paper. The
 * photo goes straight to private storage (presigned PUT), then the request
 * is sent to the Palee team. Only one person of the team sees it, and it is
 * deleted on the decision or after the retention days.
 */
export function SelfieStep({ token, request, limits }: { token: string; request: VerificationRequest; limits: VerificationLimits }) {
  const t = useTranslations("PartnerVerify");
  const queryClient = useQueryClient();
  const inputId = useId();
  const cameraRef = useRef<HTMLInputElement>(null);
  const fileRef = useRef<HTMLInputElement>(null);
  const [file, setFile] = useState<File | null>(null);
  const [problem, setProblem] = useState<SelfieProblem>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [progress, setProgress] = useState<number | null>(null);
  const previewRef = useRef<string | null>(null);
  useEffect(() => () => {
    if (previewRef.current) URL.revokeObjectURL(previewRef.current);
  }, []);
  function showPreview(picked: File | null) {
    if (previewRef.current) URL.revokeObjectURL(previewRef.current);
    previewRef.current = picked ? URL.createObjectURL(picked) : null;
    setPreview(previewRef.current);
  }

  const submit = useMutation({
    mutationFn: async (picked: File) => {
      const contentType = selfieContentType(picked, limits.selfie_content_types);
      if (!contentType) throw new Error("type");
      const upload = await selfieUploadUrl(token, contentType);
      setProgress(0);
      await putPresigned(upload.upload_url, picked, upload.required_headers, {
        onProgress: (loaded, total) => setProgress(total > 0 ? Math.round((loaded / total) * 100) : null),
      });
      return submitVerification(token, upload.file_key);
    },
    onSuccess: (next) => queryClient.setQueryData(VERIFICATION_KEY, next),
    onSettled: () => setProgress(null),
  });

  function pick(picked: File | undefined) {
    if (!picked) return;
    const found = selfieProblem(picked, limits.selfie_content_types, limits.selfie_max_bytes);
    setProblem(found);
    setFile(found ? null : picked);
    showPreview(found ? null : picked);
    submit.reset();
  }

  const fieldError = errorFor(submit.error, "selfie");
  const maxMb = Math.round(limits.selfie_max_bytes / (1024 * 1024));

  return (
    <div className="flex min-w-0 flex-col gap-3" data-testid="selfie-step">
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("selfie.write")}</p>
      <p
        className="self-center rounded-2xl px-6 py-3 font-mono text-4xl font-bold tracking-[0.3em]"
        style={{ background: "var(--panel-raised)", color: "var(--text)" }}
        dir="ltr"
        data-testid="selfie-code"
        aria-label={t("selfie.codeLabel", { code: request.selfie_code.split("").join(" ") })}
      >
        {request.selfie_code}
      </p>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("selfie.hold")}</p>
      <input
        ref={cameraRef}
        id={inputId}
        type="file"
        accept={limits.selfie_content_types.join(",")}
        capture="user"
        className="sr-only"
        tabIndex={-1}
        aria-hidden="true"
        onChange={(event) => pick(event.target.files?.[0])}
      />
      <input
        ref={fileRef}
        type="file"
        accept={limits.selfie_content_types.join(",")}
        className="sr-only"
        tabIndex={-1}
        aria-hidden="true"
        data-testid="selfie-file"
        onChange={(event) => pick(event.target.files?.[0])}
      />
      {preview ? (
        // eslint-disable-next-line @next/next/no-img-element -- a local preview of the picked photo
        <img src={preview} alt={t("selfie.previewAlt")} className="max-h-72 w-auto self-center rounded-2xl object-contain" />
      ) : null}
      <div className="flex flex-wrap gap-2">
        <button type="button" className={primaryButton} style={file ? secondaryStyle : primaryStyle} onClick={() => cameraRef.current?.click()} disabled={submit.isPending}>
          <VerifyIcon name="camera" /> {file ? t("selfie.retake") : t("selfie.take")}
        </button>
        <button type="button" className={primaryButton} style={secondaryStyle} onClick={() => fileRef.current?.click()} disabled={submit.isPending}>
          {t("selfie.choose")}
        </button>
      </div>
      {problem ? (
        <ErrorNotice variant="field">{problem === "size" ? t("selfie.tooBig", { mb: maxMb }) : t("selfie.wrongType")}</ErrorNotice>
      ) : null}
      {fieldError ? <VerifyError error={fieldError} field /> : null}
      {!fieldError && submit.error ? <VerifyError error={submit.error} /> : null}
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("selfie.privacy", { days: limits.selfie_retention_days })}</p>
      {file ? (
        <button type="button" className={`${primaryButton} self-start`} style={primaryStyle} disabled={submit.isPending} onClick={() => submit.mutate(file)}>
          {submit.isPending ? (progress !== null ? t("selfie.uploading", { percent: progress }) : t("selfie.sending")) : t("selfie.submit")}
        </button>
      ) : null}
    </div>
  );
}
