"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { BODY_KEY, deleteBodySnapshot, fetchBodySnapshot } from "@/api/body";
import { LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { ErrorLine } from "@/components/community/Sheet";
import {
  BodyPhotoView,
  Card,
  Eyebrow,
  IconButton,
  MetricValue,
  PillButton,
  PrivacyLine,
  ShareIcon,
  dateFormat,
  key,
} from "@/components/body/BodyBits";
import { MeasureForm } from "@/components/body/MeasureForm";
import { ShareBeforeAfterDialog } from "@/components/body/ShareBeforeAfter";
import { bodyErrorMessage } from "@/components/body/errors";
import { useBodySettings, useBodySnapshots, useBodyToken } from "@/components/body/use-body";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { METRICS, POSES, recordedMetrics, sharedPoses } from "@/lib/body";
import { BackLink } from "@/components/ui/BackLink";

function useSnapshot(snapshotId: string) {
  const token = useBodyToken();
  return useQuery({
    queryKey: [...BODY_KEY, "snapshot", snapshotId],
    enabled: Boolean(token),
    queryFn: () => fetchBodySnapshot(token!, snapshotId),
  });
}

/** One snapshot: its photos (blurred until tapped when set), values, who sees it, edit, delete and share. */
export function SnapshotDetail({ snapshotId }: { snapshotId: string }) {
  const t = useTranslations("Body");
  const tUi = useUiTranslations();
  const locale = useUiLocale();
  const router = useRouter();
  const queryClient = useQueryClient();
  const token = useBodyToken();
  const snapshot = useSnapshot(snapshotId);
  const settings = useBodySettings();
  const history = useBodySnapshots();
  const list = useMemo(() => history.data?.pages.flatMap((page) => page.snapshots) ?? [], [history.data]);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sharing, setSharing] = useState(false);

  if (snapshot.isPending || settings.isPending) return <LoadingLine />;
  if (snapshot.isError) return <QueryProblem error={snapshot.error} onRetry={() => void snapshot.refetch()} />;
  if (settings.isError) return <QueryProblem error={settings.error} onRetry={() => void settings.refetch()} />;

  const data = snapshot.data;
  const dates = dateFormat(locale);
  const blur = settings.data.settings.blur_photos;
  const metrics = recordedMetrics(data);
  const partner = list
    .filter((item) => item.id !== data.id && sharedPoses(item, data).length > 0)
    .sort((a, b) => a.taken_at.localeCompare(b.taken_at))[0];

  async function remove() {
    if (!token) return;
    setDeleting(true);
    setError(null);
    try {
      await deleteBodySnapshot(token, data.id);
      await queryClient.invalidateQueries({ queryKey: BODY_KEY });
      void queryClient.invalidateQueries({ queryKey: ["my", "journal"] });
      router.push("/journal/body");
    } catch (caught) {
      setError(bodyErrorMessage(caught, t, tUi));
      setDeleting(false);
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <BackLink href="/journal/body" className="text-sm font-semibold" style={{ color: "var(--primary)" }}>{t("title")}</BackLink>
          <h2 className="mt-1 text-xl font-extrabold" style={{ color: "var(--text)" }}>{dates.dateTime(data.taken_at)}</h2>
          <p className="text-sm" style={{ color: "var(--dim)" }}>
            {data.source === "garmin" ? [t(key("visibility", data.visibility)), t("fromGarmin")].join(" · ") : t(key("visibility", data.visibility))}
          </p>
        </div>
        {partner ? (
          <IconButton label={t("shareAria")} onClick={() => setSharing(true)}>
            <ShareIcon />
          </IconButton>
        ) : null}
      </div>

      {data.photos.length ? (
        <Card label={t("photosLabel")}>
          <div className="grid grid-cols-3 gap-2">
            {POSES.map((pose) => (
              <BodyPhotoView
                key={pose}
                photo={data.photos.find((photo) => photo.pose === pose)}
                blur={blur}
                label={t(key("pose", pose))}
                className="aspect-[3/4]"
              />
            ))}
          </div>
          <PrivacyLine>{data.visibility === "coach_full" ? t("photosCoach") : t("photosPrivate")}</PrivacyLine>
        </Card>
      ) : null}

      {metrics.length ? (
        <Card label={t("measurementsLabel")}>
          <Eyebrow>{t("measurementsLabel")}</Eyebrow>
          <dl className="flex flex-col">
            {METRICS.filter((metric) => metrics.includes(metric)).map((metric) => (
              <div key={metric} className="flex justify-between gap-3 border-b py-2 text-sm last:border-b-0" style={{ borderColor: "var(--border)" }}>
                <dt style={{ color: "var(--text)" }}>{t(key("metric", metric))}</dt>
                <dd className="font-semibold" style={{ color: "var(--text)" }}>
                  <MetricValue snapshot={data} metric={metric} catalog={settings.data.catalog} locale={locale} />
                </dd>
              </div>
            ))}
          </dl>
        </Card>
      ) : null}

      {data.notes ? (
        <Card label={t("notesLabel")}>
          <Eyebrow>{t("notesLabel")}</Eyebrow>
          <p className="whitespace-pre-wrap text-sm" style={{ color: "var(--text-soft)" }}>{data.notes}</p>
        </Card>
      ) : null}

      <div className="flex flex-wrap gap-2">
        <Link
          href={`/journal/body/${data.id}/edit`}
          className="flex min-h-11 flex-1 items-center justify-center rounded-2xl px-4 text-sm font-bold"
          style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("edit")}
        </Link>
        {list.length > 1 ? (
          <Link
            href={`/journal/body/compare?to=${encodeURIComponent(data.id)}`}
            className="flex min-h-11 flex-1 items-center justify-center rounded-2xl px-4 text-sm font-bold"
            style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {t("compareWith")}
          </Link>
        ) : null}
        <PillButton danger onClick={() => setConfirmDelete(true)}>{t("delete")}</PillButton>
      </div>

      {confirmDelete ? (
        <Card label={t("deleteTitle")}>
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("deleteTitle")}</p>
          <p className="text-sm" style={{ color: "var(--muted)" }}>{t("deleteBody")}</p>
          <div className="flex gap-2">
            <PillButton onClick={() => setConfirmDelete(false)}>{t("cancel")}</PillButton>
            <PillButton danger disabled={deleting} onClick={() => void remove()}>{t("deleteConfirm")}</PillButton>
          </div>
        </Card>
      ) : null}
      <ErrorLine message={error} />

      {sharing && partner ? <ShareBeforeAfterDialog snapshots={list} fromId={partner.id} toId={data.id} onClose={() => setSharing(false)} /> : null}
    </div>
  );
}

/** Editing one snapshot. */
export function EditSnapshot({ snapshotId }: { snapshotId: string }) {
  const snapshot = useSnapshot(snapshotId);
  if (snapshot.isPending) return <LoadingLine />;
  if (snapshot.isError) return <QueryProblem error={snapshot.error} onRetry={() => void snapshot.refetch()} />;
  return <MeasureForm snapshot={snapshot.data} />;
}
