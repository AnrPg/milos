"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import {
  checkPlatformFiscalConnection,
  fetchPlatformFiscalConnections,
  savePlatformFiscalConnection,
  setPlatformConnectionsManager,
  type ConnectionKind,
  type ConnectionsManager,
  type ConnectionsOverview,
} from "@/api/fiscal";
import { ConnectionPanel, ConnectionRows, type ConnectionsApi } from "@/components/fiscal/FiscalConnections";
import { countryName, hintStyle } from "@/components/fiscal/fiscal-ui";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formErrorsFrom } from "@/lib/form-errors";

const MANAGERS: ConnectionsManager[] = ["owner", "palee"];

/**
 * Vendor console › a box's fiscal connections (ADR-273): the Palee team
 * chooses who manages them and can fill or replace any of them with the
 * owner's own form. Every change is audited; secrets are never shown.
 */
export function PlatformFiscalConnectionsDialog({
  token,
  organizationId,
  organizationName,
  onClose,
}: {
  token: string;
  organizationId: string;
  organizationName: string;
  onClose: () => void;
}) {
  const t = useTranslations("FiscalConnections");
  const translate = useUiTranslations();
  const locale = useUiLocale();
  const queryClient = useQueryClient();
  const queryKey = ["platform", "organizations", organizationId, "fiscal-connections"] as const;
  const overview = useQuery({ queryKey, enabled: Boolean(token), queryFn: () => fetchPlatformFiscalConnections(token, organizationId) });
  const [open, setOpen] = useState<ConnectionKind | null>(null);
  const [error, setError] = useState<string | null>(null);

  const manager = useMutation({
    mutationFn: (managedBy: ConnectionsManager) => setPlatformConnectionsManager(token, organizationId, managedBy),
    onSuccess: (data) => {
      setError(null);
      queryClient.setQueryData<ConnectionsOverview>(queryKey, data);
    },
    onError: (failure) => setError(formErrorsFrom(failure, translate, []).message),
  });

  const api: ConnectionsApi = {
    queryKey,
    save: (kind, body) => savePlatformFiscalConnection(token, organizationId, kind, body),
    check: (kind) => checkPlatformFiscalConnection(token, organizationId, kind),
  };

  if (open && overview.data) {
    return <ConnectionPanel kind={open} overview={overview.data} api={api} readOnly={false} onClose={() => setOpen(null)} />;
  }

  const country = overview.data?.country ?? null;

  return (
    <Dialog
      variant="panel"
      size="md"
      title={t("platform.title", { name: organizationName })}
      onClose={onClose}
      error={error}
      testId="platform-fiscal-connections"
    >
      {overview.isPending ? null : overview.isError ? (
        <ErrorNotice>{t("loadFailed")}</ErrorNotice>
      ) : (
        <div className="grid gap-3">
          <div className="grid gap-1">
            <span className="text-xs font-bold" style={{ color: "var(--text-soft)" }}>{t("platform.managedBy")}</span>
            <div role="radiogroup" aria-label={t("platform.managedBy")} className="inline-flex w-fit rounded-xl p-0.5" style={{ background: "var(--panel-muted)" }}>
              {MANAGERS.map((option) => {
                const on = overview.data.managed_by === option;
                return (
                  <button
                    key={option}
                    type="button"
                    role="radio"
                    aria-checked={on}
                    disabled={manager.isPending}
                    onClick={() => (on ? undefined : manager.mutate(option))}
                    data-testid={`platform-fiscal-manager-${option}`}
                    className="rounded-lg px-3 py-1.5 text-sm font-bold"
                    style={on ? { background: "var(--panel)", color: "var(--text)", boxShadow: "0 0 0 1px var(--border)" } : { color: "var(--text-soft)" }}
                  >
                    {t(`platform.${option}`)}
                  </button>
                );
              })}
            </div>
            <span className="text-xs" style={hintStyle}>{t("platform.managedHint")}</span>
          </div>
          {country ? (
            <ConnectionRows overview={overview.data} countryName={countryName(locale, country)} selected={null} onOpen={setOpen} />
          ) : (
            <p className="text-sm" style={hintStyle}>{t("platform.empty")}</p>
          )}
        </div>
      )}
    </Dialog>
  );
}
