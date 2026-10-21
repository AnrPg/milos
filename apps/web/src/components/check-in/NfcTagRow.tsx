"use client";

import { useState, useSyncExternalStore } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchNfcTag, nfcTagKey, rotateNfcTag, setNfcTagEnabled } from "@/api/check-in";
import { nfcWriter, writeNfcTag } from "@/lib/platform/nfc";

import { ConfirmButton } from "./ConfirmButton";

const noSubscription = () => () => {};

/**
 * The location's NFC door tag (ADR-173), next to its printed poster: on or
 * off, write the link to a tag from this phone (the store app, or Chrome on
 * Android), copy it for any NFC app, and give it a new code (every tag
 * written so far stops working). A tag tap only checks in to a booking.
 */
export function NfcTagRow({ token, locationId }: { token: string; locationId: string }) {
  const t = useTranslations("CheckIn");
  const queryClient = useQueryClient();
  const [notice, setNotice] = useState<{ tone: "ok" | "error"; text: string } | null>(null);
  const tag = useQuery({ queryKey: nfcTagKey(locationId), queryFn: () => fetchNfcTag(token, locationId) });
  // The server render and the first client render agree (no writer).
  const writer = useSyncExternalStore(noSubscription, nfcWriter, () => null);

  const store = (data: Awaited<ReturnType<typeof fetchNfcTag>>) => queryClient.setQueryData(nfcTagKey(locationId), data);
  const toggle = useMutation({
    mutationFn: (enabled: boolean) => setNfcTagEnabled(token, locationId, enabled),
    onSuccess: store,
    onError: () => setNotice({ tone: "error", text: t("errorGeneric") }),
  });
  const rotate = useMutation({
    mutationFn: () => rotateNfcTag(token, locationId),
    onSuccess: (data) => {
      store(data);
      setNotice({ tone: "ok", text: t("nfcRotated") });
    },
    onError: () => setNotice({ tone: "error", text: t("errorGeneric") }),
  });
  const write = useMutation({
    mutationFn: (url: string) => writeNfcTag(url, writer),
    onMutate: () => setNotice({ tone: "ok", text: t("nfcHoldNear") }),
    onSuccess: () => setNotice({ tone: "ok", text: t("nfcWritten") }),
    onError: () => setNotice({ tone: "error", text: t("nfcWriteFailed") }),
  });

  async function copy(url: string) {
    try {
      await navigator.clipboard.writeText(url);
      setNotice({ tone: "ok", text: t("nfcCopied") });
    } catch {
      setNotice({ tone: "error", text: t("errorGeneric") });
    }
  }

  const enabled = tag.data?.enabled ?? false;
  const link = tag.data?.deep_link ?? "";

  return (
    <div className="flex flex-col gap-3 rounded-2xl px-4 py-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="nfc-tag">
      <label className="flex items-start justify-between gap-4">
        <span className="flex flex-col">
          <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("nfcTitle")}</span>
          <span className="text-sm" style={{ color: "var(--text-soft)" }}>{t("nfcHint")}</span>
        </span>
        <input
          type="checkbox"
          role="switch"
          className="mt-1 h-5 w-5 shrink-0"
          checked={enabled}
          disabled={!tag.data || toggle.isPending}
          onChange={(event) => toggle.mutate(event.target.checked)}
        />
      </label>
      {enabled && link ? (
        <div className="flex flex-wrap items-start gap-2">
          {writer ? (
            <button
              type="button"
              disabled={write.isPending}
              onClick={() => write.mutate(link)}
              className="flex min-h-11 items-center rounded-2xl px-4 text-sm font-bold disabled:opacity-60"
              style={{ background: "var(--primary)", color: "var(--bg)" }}
            >
              {t("nfcWrite")}
            </button>
          ) : null}
          <button
            type="button"
            onClick={() => void copy(link)}
            className="flex min-h-11 items-center rounded-2xl px-4 text-sm font-bold"
            style={{ border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {t("nfcCopy")}
          </button>
          <ConfirmButton
            label={t("newNfcCode")}
            question={t("newNfcCodeConfirm")}
            confirmLabel={t("newNfcCodeAction")}
            pending={rotate.isPending}
            onConfirm={() => rotate.mutate()}
          />
        </div>
      ) : null}
      {enabled && !writer ? <p className="text-xs" style={{ color: "var(--dim)" }}>{t("nfcWriteElsewhere")}</p> : null}
      {notice ? (
        <p role={notice.tone === "error" ? "alert" : "status"} className="text-sm" style={{ color: notice.tone === "error" ? "var(--danger)" : "var(--success)" }}>
          {notice.text}
        </p>
      ) : null}
    </div>
  );
}
