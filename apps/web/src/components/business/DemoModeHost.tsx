"use client";

import { useEffect, useRef, useState } from "react";
import { usePathname } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  ADMIN_BUSINESS_KEY,
  demoSectionForPath,
  fetchBusinessStatus,
  isAdminPath,
  removeDemoData,
  requestActivation,
  seedDemoData,
  type BusinessDemoStatus,
  type DemoSection,
} from "@/api/business-accounts";
import { BUSINESS_NOT_ACTIVATED_EVENT } from "@/api/client";
import { useSession } from "@/components/session-provider";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { Popover } from "@/components/ui/Popover";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { FRESHNESS } from "@/lib/query-policy";

/**
 * ADR-184: a gym or coach in demo mode. On every admin screen one floating
 * button fills that screen with demo data (server-side seeders, ordinary
 * rows), removes it, and asks the Palee team for activation. Anywhere in the
 * app, a `business_not_activated` refusal opens one friendly notice
 * («Ενεργοποίηση από την ομάδα Palee») with the same request.
 */
export function DemoModeHost() {
  const pathname = usePathname() ?? "";
  const { tokens } = useSession();
  const { membership } = useSelectedMembershipRole();
  const [noticeOpen, setNoticeOpen] = useState(false);
  const token = tokens?.access_token ?? null;
  // Only an explicit "demo" gates: a payload without the field is an active business.
  const demo = membership?.organization?.activation === "demo";
  const roles = membership?.roles ?? [];
  const manages = roles.includes("owner") || roles.includes("admin");
  const enabled = Boolean(token && demo && manages);

  useEffect(() => {
    const open = () => setNoticeOpen(true);
    window.addEventListener(BUSINESS_NOT_ACTIVATED_EVENT, open);
    return () => window.removeEventListener(BUSINESS_NOT_ACTIVATED_EVENT, open);
  }, []);

  const status = useQuery({
    queryKey: [...ADMIN_BUSINESS_KEY, membership?.organization.slug],
    enabled,
    queryFn: () => fetchBusinessStatus(token!),
    staleTime: FRESHNESS.account,
  });

  return (
    <>
      {enabled && isAdminPath(pathname) && status.data?.gated ? (
        <DemoButton token={token!} status={status.data} section={demoSectionForPath(pathname)} />
      ) : null}
      {noticeOpen ? (
        <NotActivatedNotice
          token={enabled ? token : null}
          status={status.data ?? null}
          onClose={() => setNoticeOpen(false)}
        />
      ) : null}
    </>
  );
}

function useBusinessMutations(token: string | null) {
  const queryClient = useQueryClient();
  // Every screen reads its own queries; the demo rows land in all of them.
  const refresh = (next: BusinessDemoStatus) => {
    queryClient.setQueriesData({ queryKey: ADMIN_BUSINESS_KEY }, next);
    void queryClient.invalidateQueries();
  };

  const seed = useMutation({
    mutationFn: (section: DemoSection | "all") => seedDemoData(token!, section),
    onSuccess: refresh,
  });
  const remove = useMutation({ mutationFn: () => removeDemoData(token!), onSuccess: refresh });
  const request = useMutation({
    mutationFn: () => requestActivation(token!),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ADMIN_BUSINESS_KEY }),
  });

  return { seed, remove, request };
}

function DemoButton({
  token,
  status,
  section,
}: {
  token: string;
  status: BusinessDemoStatus;
  section: DemoSection | "all";
}) {
  const t = useTranslations("Business");
  const i18n = useUiTranslations();
  const anchorRef = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  const [confirmRemove, setConfirmRemove] = useState(false);
  const { seed, remove, request } = useBusinessMutations(token);
  const seeded = status.sections.filter((entry) => entry.seeded);
  const screenSeeded =
    section === "all"
      ? status.sections.every((entry) => entry.seeded)
      : Boolean(status.sections.find((entry) => entry.section === section)?.seeded);
  const pending = status.activation_request?.status === "pending";
  const busy = seed.isPending || remove.isPending;
  const error = seed.error ?? remove.error ?? request.error;

  return (
    <>
      <button
        ref={anchorRef}
        type="button"
        aria-haspopup="dialog"
        aria-expanded={open}
        onClick={() => {
          setConfirmRemove(false);
          setOpen((value) => !value);
        }}
        className="fixed bottom-[calc(var(--bottom-float-inset)+1rem)] end-4 z-(--z-sticky) flex min-h-12 items-center gap-2 rounded-full px-5 text-sm font-bold shadow-lg"
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        data-testid="demo-mode-button"
      >
        <span aria-hidden="true">✦</span>
        {busy ? t("demo.working") : t("demo.button")}
      </button>
      <Popover
        anchorRef={anchorRef}
        open={open}
        onClose={() => setOpen(false)}
        align="end"
        width={320}
        role="dialog"
        ariaLabel={t("demo.title")}
        className="rounded-3xl p-4 shadow-lg"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        <div className="flex flex-col gap-3">
          <div>
            <p className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>
              {t("demo.eyebrow")}
            </p>
            <p className="mt-1 text-base font-semibold" style={{ color: "var(--text)" }}>{t("demo.title")}</p>
            <p className="mt-1 text-sm" style={{ color: "var(--text-soft)" }}>{t("demo.intro")}</p>
          </div>

          <DialogButton
            tone="primary"
            disabled={busy || screenSeeded}
            onClick={() => seed.mutate(section)}
          >
            {screenSeeded ? t("demo.filled") : t(`demo.fill.${section}`)}
          </DialogButton>
          {section !== "all" && !status.sections.every((entry) => entry.seeded) ? (
            <DialogButton disabled={busy} onClick={() => seed.mutate("all")}>
              {t("demo.fill.all")}
            </DialogButton>
          ) : null}
          {seeded.length > 0 ? (
            confirmRemove ? (
              <div className="flex flex-col gap-2 rounded-2xl p-3" style={{ background: "var(--panel-raised)" }}>
                <p className="text-sm" style={{ color: "var(--text)" }}>{t("demo.removeConfirm")}</p>
                <div className="flex gap-2">
                  <DialogButton tone="danger" disabled={busy} onClick={() => remove.mutate()}>
                    {t("demo.removeYes")}
                  </DialogButton>
                  <DialogButton tone="ghost" onClick={() => setConfirmRemove(false)}>
                    {t("common.cancel")}
                  </DialogButton>
                </div>
              </div>
            ) : (
              <DialogButton tone="ghost" disabled={busy} onClick={() => setConfirmRemove(true)}>
                {t("demo.remove")}
              </DialogButton>
            )
          ) : null}

          <div className="border-t pt-3" style={{ borderColor: "var(--border)" }}>
            {pending ? (
              <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("activation.pending")}</p>
            ) : (
              <DialogButton disabled={request.isPending} onClick={() => request.mutate()} className="w-full">
                {t("activation.request")}
              </DialogButton>
            )}
          </div>
          {error ? (
            <ErrorNotice>{localizeError(error, i18n)}</ErrorNotice>
          ) : null}
        </div>
      </Popover>
    </>
  );
}

function NotActivatedNotice({
  token,
  status,
  onClose,
}: {
  token: string | null;
  status: BusinessDemoStatus | null;
  onClose: () => void;
}) {
  const t = useTranslations("Business");
  const i18n = useUiTranslations();
  const { request } = useBusinessMutations(token);
  const pending = status?.activation_request?.status === "pending" || request.isSuccess;

  return (
    <Dialog
      onClose={onClose}
      eyebrow={t("notice.eyebrow")}
      title={t("notice.title")}
      size="md"
      footer={
        <>
          <DialogButton tone="ghost" onClick={onClose}>{t("common.close")}</DialogButton>
          {token && !pending ? (
            <DialogButton tone="primary" disabled={request.isPending} onClick={() => request.mutate()}>
              {t("activation.request")}
            </DialogButton>
          ) : null}
        </>
      }
    >
      <div className="flex flex-col gap-3 text-sm" style={{ color: "var(--text-soft)" }}>
        <p>{t("notice.body")}</p>
        <ul className="flex flex-col gap-1">
          {(["people", "public", "bookings", "payments", "messages"] as const).map((item) => (
            <li key={item} className="flex gap-2">
              <span aria-hidden="true" style={{ color: "var(--dim)" }}>•</span>
              {t(`notice.locked.${item}`)}
            </li>
          ))}
        </ul>
        <p style={{ color: "var(--text)" }}>
          {pending ? t("activation.pending") : token ? t("notice.howOwner") : t("notice.howStaff")}
        </p>
        {request.error ? (
          <ErrorNotice>{localizeError(request.error, i18n)}</ErrorNotice>
        ) : null}
      </div>
    </Dialog>
  );
}
