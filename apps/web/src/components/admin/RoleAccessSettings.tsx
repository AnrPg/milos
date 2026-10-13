"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { fetchRoleAccess, updateRoleAccess } from "@/api/roles";
import { localizeError } from "@/i18n/presentation";
import { SemanticLabel } from "@/components/semantic-label";
import { useUiTranslations } from "@/i18n/ui";

const CAPABILITY_LABELS: Record<string, string> = {
  manage_billing: "roleAccessBilling",
  manage_promotions: "roleAccessPromotions",
  manage_packages: "roleAccessPackages",
  view_finance_reports: "roleAccessReports",
};

/** What this gym unlocks for front desk in Finance (navigation-by-role §3). */
export function RoleAccessSettings({ token }: { token: string }) {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const access = useQuery({ queryKey: ["admin", "role-access"], queryFn: () => fetchRoleAccess(token) });
  const mutation = useMutation({
    mutationFn: ({ role, capabilities }: { role: string; capabilities: string[] }) =>
      updateRoleAccess(token, role, capabilities),
    onSuccess: (data) => {
      queryClient.setQueryData(["admin", "role-access"], data);
      void queryClient.invalidateQueries({ queryKey: ["organization-memberships"] });
    },
  });

  if (access.isPending) return <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>;
  if (access.isError) return <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{localizeError(access.error, i18n)}</p>;

  return (
    <div className="space-y-6">
      {Object.entries(access.data.grantable).map(([role, grantable]) => {
        const granted = access.data.grants[role] ?? [];
        return (
          <fieldset key={role} className="space-y-3">
            <legend className="text-sm font-semibold" style={{ color: "var(--text)" }}>
              <SemanticLabel value={role} />
            </legend>
            <p className="text-xs" style={{ color: "var(--dim)" }}>{i18n("roleAccessAlwaysOn")}</p>
            {grantable.map((capability) => {
              const checked = granted.includes(capability);
              return (
                <label key={capability} className="flex items-center gap-3 text-sm" style={{ color: "var(--text-soft)" }}>
                  <input
                    type="checkbox"
                    checked={checked}
                    disabled={mutation.isPending}
                    onChange={() =>
                      mutation.mutate({
                        role,
                        capabilities: checked ? granted.filter((item) => item !== capability) : [...granted, capability],
                      })
                    }
                  />
                  {CAPABILITY_LABELS[capability] ? i18n(CAPABILITY_LABELS[capability]) : capability}
                </label>
              );
            })}
          </fieldset>
        );
      })}
      {mutation.isError ? <p role="alert" className="text-sm" style={{ color: "var(--danger)" }}>{localizeError(mutation.error, i18n)}</p> : null}
    </div>
  );
}
