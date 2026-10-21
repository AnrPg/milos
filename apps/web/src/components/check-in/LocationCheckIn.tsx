"use client";

import Link from "next/link";
import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchPoster, posterKey, rotateDoor, rotatePoster, setPosterEnabled } from "@/api/check-in";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { ConfirmButton } from "./ConfirmButton";
import { NfcTagRow } from "./NfcTagRow";

/**
 * Check-in at one location (ADR-155): open its door screen, give the door a
 * new code (every QR shown so far stops working), and the printed poster:
 * on or off, print it, give it a new code; and the NFC door tag (ADR-173). Lives in the location's settings,
 * never on the kiosk itself.
 */
export function LocationCheckIn({ token, locationId }: { token: string; locationId: string }) {
  const t = useTranslations("CheckIn");
  const slug = useOrganizationSlug();
  const queryClient = useQueryClient();
  const [notice, setNotice] = useState<{ tone: "ok" | "error"; text: string } | null>(null);
  const poster = useQuery({ queryKey: posterKey(locationId), queryFn: () => fetchPoster(token, locationId) });

  const say = (tone: "ok" | "error", text: string) => setNotice({ tone, text });
  const door = useMutation({
    mutationFn: () => rotateDoor(token, locationId),
    onSuccess: () => say("ok", t("doorRotated")),
    onError: () => say("error", t("errorGeneric")),
  });
  const toggle = useMutation({
    mutationFn: (enabled: boolean) => setPosterEnabled(token, locationId, enabled),
    onSuccess: (data) => queryClient.setQueryData(posterKey(locationId), data),
    onError: () => say("error", t("errorGeneric")),
  });
  const rotate = useMutation({
    mutationFn: () => rotatePoster(token, locationId),
    onSuccess: (data) => {
      queryClient.setQueryData(posterKey(locationId), data);
      say("ok", t("posterRotated"));
    },
    onError: () => say("error", t("errorGeneric")),
  });

  const row = "flex flex-col gap-3 rounded-2xl px-4 py-3";
  const panel = { background: "var(--panel)", border: "1px solid var(--border)" };
  const enabled = poster.data?.enabled ?? false;

  return (
    <section aria-labelledby="location-check-in" className="flex flex-col gap-3" data-testid="location-check-in">
      <h2 id="location-check-in" className="text-xs font-bold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
        {t("locationSection")}
      </h2>

      <div className={row} style={panel}>
        <div className="flex flex-col">
          <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("doorScreen")}</span>
          <span className="text-sm" style={{ color: "var(--text-soft)" }}>{t("doorScreenHint")}</span>
        </div>
        <div className="flex flex-wrap items-start gap-2">
          <Link
            href={adminHref(`/admin/check-in/door/${locationId}`, slug)}
            className="flex min-h-11 items-center rounded-2xl px-4 text-sm font-bold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {t("openDoorScreen")}
          </Link>
          <ConfirmButton
            label={t("newDoorCode")}
            question={t("newDoorCodeConfirm")}
            confirmLabel={t("newDoorCodeAction")}
            pending={door.isPending}
            onConfirm={() => door.mutate()}
          />
        </div>
      </div>

      <div className={row} style={panel}>
        <label className="flex items-start justify-between gap-4">
          <span className="flex flex-col">
            <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("posterTitle")}</span>
            <span className="text-sm" style={{ color: "var(--text-soft)" }}>{t("posterHintSettings")}</span>
          </span>
          <input
            type="checkbox"
            role="switch"
            className="mt-1 h-5 w-5 shrink-0"
            checked={enabled}
            disabled={!poster.data || toggle.isPending}
            onChange={(event) => toggle.mutate(event.target.checked)}
          />
        </label>
        {enabled ? (
          <div className="flex flex-wrap items-start gap-2">
            <Link
              href={adminHref(`/admin/check-in/poster/${locationId}`, slug)}
              className="flex min-h-11 items-center rounded-2xl px-4 text-sm font-bold"
              style={{ border: "1px solid var(--border)", color: "var(--text)" }}
            >
              {t("posterShow")}
            </Link>
            <ConfirmButton
              label={t("newPosterCode")}
              question={t("newPosterCodeConfirm")}
              confirmLabel={t("newPosterCodeAction")}
              pending={rotate.isPending}
              onConfirm={() => rotate.mutate()}
            />
          </div>
        ) : null}
      </div>

      <NfcTagRow token={token} locationId={locationId} />

      {notice ? (
        <p role={notice.tone === "error" ? "alert" : "status"} className="text-sm" style={{ color: notice.tone === "error" ? "var(--danger)" : "var(--success)" }}>
          {notice.text}
        </p>
      ) : null}
    </section>
  );
}
