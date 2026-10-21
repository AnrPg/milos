"use client";

import { useId, useMemo, useState } from "react";
import { useTranslations } from "next-intl";

import type { BodyPose, BodyShareAudience, BodySnapshot } from "@/api/body";
import { shareBodyBeforeAfter } from "@/api/body";
import { ChoicePill, ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { channelName } from "@/components/community/community";
import { useMyClubs } from "@/components/community/use-community";
import { BodyPhotoView, dateFormat, key } from "@/components/body/BodyBits";
import { bodyErrorMessage } from "@/components/body/errors";
import { useBodyToken } from "@/components/body/use-body";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { sharedPoses } from "@/lib/body";

type Audience = { audience: Exclude<BodyShareAudience, "club_channel"> } | { audience: "club_channel"; channelId: string; label: string };

/**
 * Sharing a before/after as a post (ADR-158 §9, board 13): what it does,
 * the two dates, one pose, optional text, the audience; then a second,
 * separate confirmation before anything is posted. No number is ever added.
 */
export function ShareBeforeAfterDialog({
  snapshots,
  fromId,
  toId,
  onClose,
}: {
  snapshots: BodySnapshot[];
  fromId: string;
  toId: string;
  onClose: () => void;
}) {
  const t = useTranslations("Body");
  const tCommunity = useTranslations("Community");
  const tUi = useUiTranslations();
  const locale = useUiLocale();
  const token = useBodyToken();
  const labelId = useId();
  const textId = useId();
  const clubs = useMyClubs();
  const dates = dateFormat(locale);
  const withPhotos = useMemo(() => snapshots.filter((snapshot) => snapshot.photos.some((photo) => photo.status === "ready")), [snapshots]);
  const [from, setFrom] = useState(fromId);
  const [to] = useState(toId);
  const fromSnapshot = snapshots.find((snapshot) => snapshot.id === from);
  const toSnapshot = snapshots.find((snapshot) => snapshot.id === to);
  const poses = sharedPoses(fromSnapshot, toSnapshot);
  const [pickedPose, setPose] = useState<BodyPose | null>(null);
  const pose = pickedPose && poses.includes(pickedPose) ? pickedPose : (poses[0] ?? null);
  const [text, setText] = useState("");
  const [audience, setAudience] = useState<Audience>({ audience: "followers" });
  const [step, setStep] = useState<"compose" | "confirm" | "done">("compose");
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const channels = (clubs.data ?? []).flatMap((club) =>
    club.channels
      .filter((channel) => channel.can_post)
      .map((channel) => ({ id: channel.id, label: t("channelLabel", { club: club.name, channel: channelName(channel, tCommunity) }) })),
  );

  async function send() {
    if (!token || !pose || sending) return;
    setSending(true);
    setError(null);
    try {
      await shareBodyBeforeAfter(token, {
        from_snapshot_id: from,
        to_snapshot_id: to,
        pose,
        text: text.trim() || null,
        audience: audience.audience,
        ...(audience.audience === "club_channel" ? { channel_id: audience.channelId } : {}),
        confirm: true,
      });
      setStep("done");
    } catch (caught) {
      setError(bodyErrorMessage(caught, t, tUi));
    } finally {
      setSending(false);
    }
  }

  const audienceLabel =
    audience.audience === "club_channel" ? audience.label : t(key("audience", audience.audience));

  if (step === "done") {
    return (
      <Sheet labelId={labelId} title={t("shareDoneTitle")} onClose={onClose} footer={<SheetButton primary onClick={onClose}>{t("close")}</SheetButton>}>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("shareDoneBody")}</p>
      </Sheet>
    );
  }

  if (step === "confirm") {
    return (
      <Sheet
        labelId={labelId}
        title={t("shareConfirmTitle")}
        onClose={onClose}
        footer={
          <>
            <SheetButton onClick={() => setStep("compose")}>{t("back")}</SheetButton>
            <SheetButton primary disabled={sending} onClick={() => void send()}>
              {sending ? t("sharing") : t("shareConfirmAction")}
            </SheetButton>
          </>
        }
      >
        <div className="flex flex-col gap-3" data-testid="share-confirm">
          <p className="text-sm" style={{ color: "var(--text)" }}>
            {t("shareConfirmBody", {
              pose: pose ? t(key("pose", pose)) : "",
              from: fromSnapshot ? dates.day(fromSnapshot.taken_at) : "",
              to: toSnapshot ? dates.day(toSnapshot.taken_at) : "",
              audience: audienceLabel,
            })}
          </p>
          <p className="text-sm" style={{ color: "var(--muted)" }}>{t("shareNoNumbers")}</p>
          <ErrorLine message={error} />
        </div>
      </Sheet>
    );
  }

  return (
    <Sheet
      labelId={labelId}
      title={t("shareTitle")}
      onClose={onClose}
      footer={
        <>
          <SheetButton onClick={onClose}>{t("cancel")}</SheetButton>
          <SheetButton primary disabled={!pose} onClick={() => setStep("confirm")}>{t("next")}</SheetButton>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("shareExplain")}</p>

        <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("shareBefore")}
          <select
            value={from}
            onChange={(event) => setFrom(event.target.value)}
            className="min-h-11 rounded-xl px-3"
            style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {withPhotos
              .filter((snapshot) => snapshot.id !== to)
              .map((snapshot) => (
                <option key={snapshot.id} value={snapshot.id}>{dates.dayYear(snapshot.taken_at)}</option>
              ))}
          </select>
        </label>

        <div role="radiogroup" aria-label={t("posesLabel")} className="flex flex-wrap gap-2">
          {poses.length ? (
            poses.map((item) => (
              <ChoicePill key={item} selected={item === pose} onSelect={() => setPose(item)}>
                {t(key("pose", item))}
              </ChoicePill>
            ))
          ) : (
            <p className="text-sm" style={{ color: "var(--muted)" }}>{t("shareNoPose")}</p>
          )}
        </div>

        {pose && fromSnapshot && toSnapshot ? (
          <div className="grid grid-cols-2 gap-1.5">
            <BodyPhotoView photo={fromSnapshot.photos.find((photo) => photo.pose === pose)} blur={false} label={dates.day(fromSnapshot.taken_at)} size="thumb" className="aspect-[3/4]" />
            <BodyPhotoView photo={toSnapshot.photos.find((photo) => photo.pose === pose)} blur={false} label={dates.day(toSnapshot.taken_at)} size="thumb" className="aspect-[3/4]" />
          </div>
        ) : null}

        <label htmlFor={textId} className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("shareText")}</label>
        <textarea
          id={textId}
          value={text}
          rows={3}
          maxLength={2000}
          onChange={(event) => setText(event.target.value)}
          placeholder={t("shareTextPlaceholder")}
          className="rounded-2xl p-3 text-sm"
          style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
        />

        <fieldset className="flex flex-col gap-2">
          <legend className="mb-1 text-sm font-semibold" style={{ color: "var(--text)" }}>{t("shareAudience")}</legend>
          <div role="radiogroup" aria-label={t("shareAudience")} className="flex flex-col gap-2">
            {(["followers", "public"] as const).map((item) => (
              <ChoicePill key={item} selected={audience.audience === item} onSelect={() => setAudience({ audience: item })} hint={t(key("audienceHint", item))}>
                {t(key("audience", item))}
              </ChoicePill>
            ))}
            {channels.map((channel) => (
              <ChoicePill
                key={channel.id}
                selected={audience.audience === "club_channel" && audience.channelId === channel.id}
                onSelect={() => setAudience({ audience: "club_channel", channelId: channel.id, label: channel.label })}
              >
                {channel.label}
              </ChoicePill>
            ))}
          </div>
        </fieldset>
      </div>
    </Sheet>
  );
}
