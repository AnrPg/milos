"use client";

import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useFormatter, useTranslations } from "next-intl";

import {
  cancelAccountDeletion,
  fetchAccountDeletion,
  requestAccountDeletion,
  type AccountDeletion,
} from "@/api/account-deletion";
import { deletionFailure, type DeletionScope } from "@/components/account/account-deletion-model";
import { CollapsibleSection } from "@/components/profile/CollapsibleSection";
import { useSession } from "@/components/session-provider";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

const DELETION_QUERY_KEY = ["account", "deletion"] as const;

const quietButton = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" } as const;
const dangerButton = { background: "var(--danger)", color: "var(--danger-contrast)" } as const;

/**
 * Ρυθμίσεις › Delete (ADR-211): delete this profile, or the account with
 * all its profiles. The password is required; a confirmed email then gets a
 * link, otherwise typing the address confirms. The deletion runs 7 days
 * later and can be undone until then. Reachable as /me/settings#delete-account.
 */
export function DeleteAccountSection() {
  const t = useTranslations("accountDeletion");
  const format = useFormatter();
  const i18n = useUiTranslations();
  const { tokens, currentUser } = useSession();
  const queryClient = useQueryClient();
  const [scope, setScope] = useState<DeletionScope | null>(null);
  const [cancelling, setCancelling] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const deletionQuery = useQuery({
    queryKey: [...DELETION_QUERY_KEY, currentUser?.id ?? null],
    queryFn: () => fetchAccountDeletion(tokens!.access_token),
    enabled: Boolean(tokens?.access_token),
  });
  const deletion = deletionQuery.data;
  const profileCount = currentUser?.profile_count ?? 1;
  const date = (at: string | null | undefined) => (at ? format.dateTime(new Date(at), { dateStyle: "long" }) : "");

  async function cancel() {
    if (!tokens) return;
    setCancelling(true);
    setError(null);
    try {
      await cancelAccountDeletion(tokens.access_token);
      await queryClient.invalidateQueries({ queryKey: DELETION_QUERY_KEY });
    } catch (caught) {
      setError(localizeError(caught, i18n));
    } finally {
      setCancelling(false);
    }
  }

  return (
    <CollapsibleSection id="delete-account" title={t("sectionTitle")} description={t("sectionDescription")}>
      <div className="space-y-4">
        {deletion?.status === "awaiting_confirmation" || deletion?.status === "scheduled" ? (
          <>
            <p className="text-sm font-semibold leading-6" style={{ color: "var(--warning)" }} role="status">
              {deletion.status === "awaiting_confirmation"
                ? t("awaiting", { email: currentUser?.email ?? "" })
                : t("scheduledProfile", { date: date(deletion.scheduled_for) })}
            </p>
            <button
              type="button"
              disabled={cancelling}
              onClick={() => void cancel()}
              className="rounded-xl px-5 py-2.5 text-sm font-semibold disabled:opacity-50"
              style={quietButton}
            >
              {deletion.status === "awaiting_confirmation" ? t("awaitingCancel") : t("undo")}
            </button>
          </>
        ) : (
          <>
            <p className="text-sm leading-6" style={{ color: "var(--muted)" }}>{t("explainer")}</p>
            <div className="flex flex-wrap gap-3">
              {profileCount > 1 ? (
                <button
                  type="button"
                  onClick={() => setScope("profile")}
                  className="rounded-xl px-5 py-2.5 text-sm font-semibold"
                  style={quietButton}
                >
                  {t("deleteProfile")}
                </button>
              ) : null}
              <button
                type="button"
                onClick={() => setScope("login")}
                className="rounded-xl px-5 py-2.5 text-sm font-semibold"
                style={dangerButton}
              >
                {t("deleteAccount")}
              </button>
            </div>
          </>
        )}
        {error ? <ErrorNotice>{error}</ErrorNotice> : null}
      </div>
      {scope ? (
        <DeleteAccountDialog
          scope={scope}
          onClose={() => setScope(null)}
          onRequested={() => void queryClient.invalidateQueries({ queryKey: DELETION_QUERY_KEY })}
        />
      ) : null}
    </CollapsibleSection>
  );
}

function DeleteAccountDialog({
  scope,
  onClose,
  onRequested,
}: {
  scope: DeletionScope;
  onClose: () => void;
  onRequested: () => void;
}) {
  const t = useTranslations("accountDeletion");
  const format = useFormatter();
  const i18n = useUiTranslations();
  const { tokens, currentUser, signOut } = useSession();
  const [password, setPassword] = useState("");
  const emailVerified = (currentUser as { email_verified?: boolean } | null)?.email_verified;
  const [askEmail, setAskEmail] = useState(emailVerified === false);
  const [confirmEmail, setConfirmEmail] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [scheduled, setScheduled] = useState<AccountDeletion | null>(null);
  const handle = currentUser?.handle ?? "";

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!tokens || pending) return;
    setPending(true);
    setError(null);
    try {
      const result = await requestAccountDeletion(tokens.access_token, {
        scope,
        password,
        ...(askEmail ? { confirm_email: confirmEmail } : {}),
      });
      setPassword("");
      if (result.status === "scheduled") {
        // Every session of what is being deleted ended, this one included.
        setScheduled(result);
      } else {
        onRequested();
        onClose();
      }
    } catch (caught) {
      const failure = deletionFailure(caught);
      if (failure?.key === "errorConfirmation") setAskEmail(true);
      setError(failure ? t(failure.key, failure.values) : localizeError(caught, i18n));
    } finally {
      setPending(false);
    }
  }

  if (scheduled) {
    const date = scheduled.scheduled_for ? format.dateTime(new Date(scheduled.scheduled_for), { dateStyle: "long" }) : "";
    return (
      <Dialog
        onClose={signOut}
        title={t("scheduledNowTitle")}
        size="md"
        dismissible={false}
        footer={
          <button
            type="button"
            onClick={signOut}
            className="w-full rounded-xl px-5 py-2.5 text-sm font-semibold sm:w-auto"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {t("signOut")}
          </button>
        }
      >
        <p className="text-sm leading-6" style={{ color: "var(--text)" }}>
          {scope === "profile" ? t("scheduledNowProfile", { date }) : t("scheduledNowAccount", { date })}
        </p>
      </Dialog>
    );
  }

  return (
    <Dialog
      onClose={onClose}
      title={scope === "profile" ? t("dialogProfileTitle", { handle }) : t("dialogAccountTitle")}
      size="md"
      dismissible={!pending}
      onSubmit={(event) => void submit(event)}
      footer={
        <div className="flex w-full gap-3 sm:w-auto">
          <button
            type="button"
            onClick={onClose}
            disabled={pending}
            className="flex-1 rounded-xl px-5 py-2.5 text-sm font-semibold sm:flex-none"
            style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
          >
            {t("cancel")}
          </button>
          <button
            type="submit"
            disabled={pending || !password || (askEmail && !confirmEmail.trim())}
            className="flex-1 rounded-xl px-5 py-2.5 text-sm font-semibold disabled:opacity-50 sm:flex-none"
            style={dangerButton}
          >
            {pending ? t("submitting") : t("submit")}
          </button>
        </div>
      }
    >
      <div className="space-y-4">
        <p className="text-sm leading-6" style={{ color: "var(--text)" }}>
          {scope === "profile"
            ? t("dialogProfileBody", { handle })
            : t("dialogAccountBody", { email: currentUser?.email ?? "" })}
        </p>
        <p className="text-sm leading-6" style={{ color: "var(--muted)" }}>{t("dialogGrace")}</p>
        <DialogField id="account-deletion-password" label={t("passwordLabel")}>
          <input
            id="account-deletion-password"
            type="password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            autoComplete="current-password"
            autoFocus
            className="w-full rounded-xl px-4 py-2.5 text-sm outline-none"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          />
        </DialogField>
        {askEmail ? (
          <DialogField id="account-deletion-email" label={t("confirmEmailLabel")} hint={t("confirmEmailHint")}>
            <input
              id="account-deletion-email"
              type="email"
              inputMode="email"
              value={confirmEmail}
              onChange={(event) => setConfirmEmail(event.target.value)}
              autoComplete="off"
              className="w-full rounded-xl px-4 py-2.5 text-sm outline-none"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            />
          </DialogField>
        ) : null}
        {error ? <ErrorNotice>{error}</ErrorNotice> : null}
      </div>
    </Dialog>
  );
}

function DialogField({
  id,
  label,
  hint,
  children,
}: {
  id: string;
  label: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="space-y-1.5">
      <label
        htmlFor={id}
        className="block text-xs font-semibold uppercase tracking-[0.18em]"
        style={{ color: "var(--muted)" }}
      >
        {label}
      </label>
      {children}
      {hint ? <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{hint}</p> : null}
    </div>
  );
}
