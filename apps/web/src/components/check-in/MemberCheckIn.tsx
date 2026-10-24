"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { addWalletPass, fetchMyCode, myCodeKey, resetMyCode, type WalletPlatform } from "@/api/check-in";
import { useSession } from "@/components/session-provider";
import { useScreenWakeLock } from "@/hooks/useScreenWakeLock";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { useOrganizationSlug } from "@/lib/organization-slug";

import { countdownLabel, memberCodeRefetchDelay } from "./check-in";
import { ArrivalReminderRow } from "./ArrivalReminderRow";
import { ConfirmButton } from "./ConfirmButton";
import { checkInErrorKey, errorCode } from "./errors";
import { QrCode } from "./QrCode";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/**
 * Box › Check-in (ADR-155 §6, vision §7.5): the member's own QR for the desk
 * to scan, big and bright. A rotating code is fetched again as it turns; a
 * code that stays the same can go in Apple or Google Wallet (when the server
 * can issue cards) and be reset if a phone is lost. The other way in is to
 * scan the door's QR with the phone camera.
 */
export function MemberCheckIn() {
  const t = useTranslations("CheckIn");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const slug = useOrganizationSlug();
  const { membership } = useSelectedMembershipRole();
  const queryClient = useQueryClient();
  const frameRef = useRef<HTMLDivElement>(null);
  const [walletMessage, setWalletMessage] = useState<string | null>(null);

  useScreenWakeLock(true);

  const code = useQuery({
    queryKey: myCodeKey(slug ?? ""),
    enabled: Boolean(token && slug),
    queryFn: () => fetchMyCode(token, slug!),
    refetchInterval: (query) => (query.state.data ? (memberCodeRefetchDelay(query.state.data) ?? false) : false),
    refetchIntervalInBackground: false,
  });
  const data = code.data;

  // The countdown under a rotating code, from when this code arrived.
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (data?.mode !== "rotating") return;
    const timer = window.setInterval(() => setNow(Date.now()), 1_000);
    return () => window.clearInterval(timer);
  }, [data?.mode]);
  const secondsLeft =
    data?.mode === "rotating" && typeof data.seconds_until_rotation === "number"
      ? Math.max(0, data.seconds_until_rotation - Math.floor((now - code.dataUpdatedAt) / 1000))
      : null;

  const reset = useMutation({
    mutationFn: () => resetMyCode(token, slug!),
    onSuccess: (fresh) => queryClient.setQueryData(myCodeKey(slug ?? ""), fresh),
  });

  const wallet = useMutation({
    mutationFn: (platform: WalletPlatform) => addWalletPass(token, slug!, platform),
    onMutate: () => setWalletMessage(null),
    onSuccess: (result) => {
      const target = result.download_url ?? result.save_url;
      if (target) window.location.assign(target);
      else setWalletMessage(t("walletAdded"));
    },
    onError: (error) => setWalletMessage(t(errorCode(error) === "wallet_not_configured" ? "walletNotConfigured" : checkInErrorKey(error))),
  });

  function fullscreen() {
    void frameRef.current?.requestFullscreen?.().catch(() => undefined);
  }

  const boxName = membership?.settings?.brand_name?.trim() || membership?.organization.name || "";

  return (
    <main className="mx-auto flex w-full max-w-xl flex-col gap-4 px-4 pb-8 pt-4">
      <header className="flex flex-col gap-1">
        <Link href="/box" className="text-sm font-semibold" style={{ color: "var(--primary-strong)" }}>‹ {t("backToBox")}</Link>
        <h1 className="text-3xl font-extrabold tracking-tight" style={{ color: "var(--text)" }}>{t("memberTitle")}</h1>
        {boxName ? <p className="text-sm" style={{ color: "var(--dim)" }}>{boxName}</p> : null}
      </header>

      <section className="flex flex-col items-center gap-3 rounded-3xl p-5 text-center" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        <div ref={frameRef} className="flex w-full flex-col items-center justify-center gap-3 rounded-3xl bg-[var(--paper)] p-4 [&:fullscreen]:h-full">
          {data ? (
            <QrCode value={data.code} label={t("memberQrLabel")} testId="member-qr" className="aspect-square w-full max-w-[22rem]" />
          ) : (
            <div className="flex aspect-square w-full max-w-[22rem] items-center justify-center text-sm" style={{ color: "var(--on-paper)", opacity: 0.65 }}>
              {code.isError ? <ErrorNotice variant="text">{t(checkInErrorKey(code.error))}</ErrorNotice> : t("loading")}
            </div>
          )}
          {secondsLeft !== null ? (
            <p className="font-mono text-sm" style={{ color: "var(--on-paper)", opacity: 0.8 }} data-testid="member-countdown">{t("memberRotatesIn", { time: countdownLabel(secondsLeft) })}</p>
          ) : null}
        </div>
        <p className="text-base font-bold" style={{ color: "var(--text)" }}>{t("memberShow")}</p>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("memberScanDoorHint")}</p>
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("brightnessHint")}</p>
        <button type="button" onClick={fullscreen} className="min-h-11 rounded-2xl px-4 text-sm font-bold" style={{ border: "1px solid var(--border)", color: "var(--text)" }}>
          {t("fullscreen")}
        </button>
        {code.isError && data ? <ErrorNotice variant="field" live="polite">{t("memberOffline")}</ErrorNotice> : null}
      </section>

      {data?.mode === "static" ? (
        <>
          {data.wallet_available ? (
            <section className="flex flex-col gap-3 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="wallet-card">
              <div>
                <h2 className="text-base font-bold" style={{ color: "var(--text)" }}>{t("walletTitle")}</h2>
                <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("walletHint")}</p>
              </div>
              <div className="flex flex-wrap gap-2">
                {(["apple", "google"] as WalletPlatform[]).map((platform) => (
                  <button
                    key={platform}
                    type="button"
                    disabled={wallet.isPending}
                    onClick={() => wallet.mutate(platform)}
                    className="min-h-11 flex-1 rounded-2xl px-4 text-sm font-bold disabled:opacity-60"
                    style={{ background: "var(--text)", color: "var(--bg)" }}
                  >
                    {t(["walletAdd", platform].join("_"))}
                  </button>
                ))}
              </div>
              {walletMessage && wallet.isError ? <ErrorNotice>{walletMessage}</ErrorNotice> : null}
              {walletMessage && !wallet.isError ? <p role="status" className="text-sm" style={{ color: "var(--text-soft)" }}>{walletMessage}</p> : null}
            </section>
          ) : null}

          <section className="flex flex-col gap-2 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <h2 className="text-base font-bold" style={{ color: "var(--text)" }}>{t("memberResetTitle")}</h2>
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("memberResetHint")}</p>
            <ConfirmButton
              label={t("memberReset")}
              question={t("memberResetConfirm")}
              confirmLabel={t("memberResetAction")}
              pending={reset.isPending}
              onConfirm={() => reset.mutate()}
              testId="member-reset"
            />
            {reset.isSuccess ? <p role="status" className="text-sm" style={{ color: "var(--success)" }}>{t("memberResetDone")}</p> : null}
            {reset.isError ? <ErrorNotice>{t(checkInErrorKey(reset.error))}</ErrorNotice> : null}
          </section>
        </>
      ) : data ? (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("memberRotatingNote")}</p>
      ) : null}

      <ArrivalReminderRow />

      <p className="text-center text-xs" style={{ color: "var(--dim)" }}>{t("memberHowItWorks")}</p>
    </main>
  );
}
