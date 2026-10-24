"use client";

import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  fetchNotificationPreferences,
  notificationPreferencesKey,
  updateNotificationPreference,
  type NotificationCategory,
  type NotificationChannel,
  type NotificationPreference,
  type NotificationPreferenceList,
} from "@/api/notifications";
import { CollapsibleSection } from "@/components/profile/CollapsibleSection";
import { PushDeviceCard } from "@/components/notifications/PushDeviceCard";
import { useSession } from "@/components/session-provider";
import { usePushNotifications } from "@/hooks/usePushNotifications";
import { useOrganizationMemberships } from "@/lib/membership-role";
import { hasStaffRole } from "@/lib/role-navigation";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

const CHANNELS: NotificationChannel[] = ["in_app", "push"];

/**
 * Εγώ › Ρυθμίσεις › Ειδοποιήσεις (ADR-199): push on this device, then one row
 * per category with a switch per channel. Account and payments are locked on;
 * the box-staff row shows only to staff. Per-club levels stay in Τα box και
 * τα clubs μου, linked from the clubs row.
 */
export function NotificationSettings() {
  const t = useTranslations("NotificationSettings");
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const push = usePushNotifications(token);
  const memberships = useOrganizationMemberships();
  const isStaff = (Array.isArray(memberships.data) ? memberships.data : []).some(hasStaffRole);
  const key = notificationPreferencesKey(currentUser?.id);

  const preferences = useQuery({
    queryKey: key,
    enabled: Boolean(token),
    queryFn: () => fetchNotificationPreferences(token!),
  });

  const save = useMutation({
    mutationFn: ({ category, change }: { category: NotificationCategory; change: Partial<Record<NotificationChannel, boolean>> }) =>
      updateNotificationPreference(token!, category, change),
    onMutate: async ({ category, change }) => {
      await queryClient.cancelQueries({ queryKey: key });
      const previous = queryClient.getQueryData<NotificationPreferenceList>(key);
      queryClient.setQueryData<NotificationPreferenceList>(key, (current) =>
        current
          ? {
              preferences: current.preferences.map((row) =>
                row.category === category ? { ...row, channels: applyChange(row.channels, change) } : row,
              ),
            }
          : current,
      );
      return { previous };
    },
    onError: (_error, _change, context) => {
      if (context?.previous) queryClient.setQueryData(key, context.previous);
    },
    onSuccess: (result) => queryClient.setQueryData(key, result),
  });

  const rows = (preferences.data?.preferences ?? []).filter((row) => row.audience !== "staff" || isStaff);

  return (
    <CollapsibleSection id="notifications" title={t("title")} description={t("description")} defaultOpen>
      <div className="space-y-5">
        {push.supported ? <PushDeviceCard push={push} isAdmin={currentUser?.role === "admin"} /> : null}

        {preferences.isPending ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
        ) : preferences.isError ? (
          <p className="text-sm font-semibold" style={{ color: "var(--danger)" }}>{t("loadError")}</p>
        ) : (
          <div role="group" aria-label={t("title")} data-testid="notification-categories">
            <div className="flex justify-end gap-3 pb-2 text-[0.68rem] font-semibold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>
              {CHANNELS.map((channel) => (
                <span key={channel} className="w-12 text-center">{t(`channel.${channel}`)}</span>
              ))}
            </div>
            {rows.map((row) => (
              <CategoryRow
                key={row.category}
                row={row}
                pending={save.isPending}
                onChange={(channel, on) =>
                  save.mutate({ category: row.category, change: { [channel]: on } as Partial<Record<NotificationChannel, boolean>> })
                }
              />
            ))}
          </div>
        )}

        {save.isError ? (
          <ErrorNotice>{t("saveError")}</ErrorNotice>
        ) : null}
      </div>
    </CollapsibleSection>
  );
}

function applyChange(
  channels: NotificationPreference["channels"],
  change: Partial<Record<NotificationChannel, boolean>>,
): NotificationPreference["channels"] {
  const next = { ...channels, ...change };
  // A push is made from the bell's notification, so it needs the bell (ADR-199).
  return next.in_app === false ? { ...next, push: false } : next;
}

function CategoryRow({
  row,
  pending,
  onChange,
}: {
  row: NotificationPreference;
  pending: boolean;
  onChange: (channel: NotificationChannel, on: boolean) => void;
}) {
  const t = useTranslations("NotificationSettings");
  const title = t(`category.${row.category}.title`);

  return (
    <div
      data-category={row.category}
      className="flex items-center justify-between gap-3 py-3"
      style={{ borderTop: "1px solid var(--border)" }}
    >
      <div className="min-w-0">
        <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{title}</p>
        <p className="mt-0.5 text-xs leading-5" style={{ color: "var(--muted)" }}>
          {t(`category.${row.category}.hint`)}
          {row.category === "community" ? (
            <>
              {" "}
              <Link href="/me/clubs" className="font-semibold underline" style={{ color: "var(--text-soft)" }}>
                {t("perClub")}
              </Link>
            </>
          ) : null}
        </p>
      </div>
      {row.locked ? (
        <span className="shrink-0 rounded-full px-3 py-1 text-xs font-semibold" style={{ background: "var(--panel-muted)", color: "var(--muted)", border: "1px solid var(--border)" }}>
          {t("locked")}
        </span>
      ) : (
        <div className="flex shrink-0 gap-3">
          {CHANNELS.map((channel) => {
            const offered = channel in row.channels;
            const on = Boolean(row.channels[channel]);
            const needsBell = channel === "push" && row.channels.in_app === false;
            return offered ? (
              <Switch
                key={channel}
                on={on}
                disabled={pending || needsBell}
                label={`${title} · ${t(`channel.${channel}`)}`}
                onChange={(next) => onChange(channel, next)}
              />
            ) : (
              <span key={channel} className="w-12" aria-hidden="true" />
            );
          })}
        </div>
      )}
    </div>
  );
}

function Switch({ on, disabled, label, onChange }: { on: boolean; disabled: boolean; label: string; onChange: (on: boolean) => void }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      aria-label={label}
      disabled={disabled}
      onClick={() => onChange(!on)}
      className="hit-area relative h-7 w-12 shrink-0 rounded-full disabled:opacity-50"
      style={{ background: on ? "var(--primary)" : "var(--panel-raised)", border: "1px solid var(--border)" }}
    >
      <span
        aria-hidden="true"
        className="absolute top-0.5 h-5 w-5 rounded-full transition-all"
        style={{ background: on ? "var(--bg)" : "var(--text)", insetInlineStart: on ? "1.5rem" : "0.2rem" }}
      />
    </button>
  );
}
