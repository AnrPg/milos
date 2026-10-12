"use client";

import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";

import { ALL_ROLES, updateCoachScope, updateMemberRoles, type RoleName } from "@/api/roles";
import { localizeError } from "@/i18n/presentation";
import { SemanticLabel } from "@/components/semantic-label";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can, membershipRoles } from "@/lib/role-navigation";
import { useUiTranslations } from "@/i18n/ui";

const STAFF: RoleName[] = ["owner", "admin", "coach", "front_desk", "accountant", "janitor"];

/** Which roles the signed-in member may hand out (mirrors MembershipPolicy). */
export function grantableRoles(actorRoles: string[]): RoleName[] {
  if (actorRoles.includes("owner")) return ALL_ROLES;
  if (actorRoles.includes("admin")) return ALL_ROLES.filter((role) => role !== "owner" && role !== "admin");
  return [];
}

/** Roles held together in this gym, and the head coach switch (ADR-099, ADR-100). */
export function MemberRolesEditor({
  token,
  userId,
  membership,
}: {
  token: string;
  userId: string;
  membership: { roles: string[]; coach_scope: string } | null | undefined;
}) {
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const { membership: actor } = useSelectedMembershipRole();
  const grantable = grantableRoles(membershipRoles(actor));
  const current = (membership?.roles ?? []) as RoleName[];
  const [draft, setDraft] = useState<RoleName[] | null>(null);
  const roles = draft ?? current;
  const changed = draft !== null && [...draft].sort().join() !== [...current].sort().join();

  const refresh = () => queryClient.invalidateQueries({ queryKey: ["admin", "users"] });
  const rolesMutation = useMutation({
    mutationFn: () => updateMemberRoles(token, userId, roles),
    onSuccess: async () => {
      setDraft(null);
      await refresh();
    },
  });
  const scopeMutation = useMutation({
    mutationFn: (scope: "own" | "all") => updateCoachScope(token, userId, scope),
    onSuccess: refresh,
  });

  if (!membership || grantable.length === 0) return null;

  const toggle = (role: RoleName) =>
    setDraft(roles.includes(role) ? roles.filter((item) => item !== role) : [...roles, role]);
  const headCoach = membership.coach_scope === "all";
  const showHeadCoach = current.includes("coach") && can(actor, "set_head_coach");
  const visible = ALL_ROLES.filter((role) => grantable.includes(role) || current.includes(role));

  return (
    <div className="space-y-4">
      <div>
        <span className="block text-xs uppercase tracking-wider" style={{ color: "var(--muted)" }}>
          {i18n("rolesInThisGym")}
        </span>
        <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{i18n("rolesInThisGymHelp")}</p>
        <div className="mt-2 flex flex-wrap gap-2">
          {visible.map((role) => {
            const selected = roles.includes(role);
            const locked = !grantable.includes(role);
            return (
              <button
                key={role}
                type="button"
                aria-pressed={selected}
                disabled={locked || rolesMutation.isPending}
                onClick={() => toggle(role)}
                className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-60"
                style={{
                  background: selected ? "var(--primary)" : "var(--bg-soft)",
                  border: `1px ${STAFF.includes(role) ? "solid" : "dashed"} var(--border)`,
                  color: selected ? "var(--bg)" : "var(--text-soft)",
                }}
              >
                <SemanticLabel value={role} />
              </button>
            );
          })}
        </div>
        {changed ? (
          <div className="mt-3 flex flex-wrap gap-2">
            <button
              type="button"
              disabled={roles.length === 0 || rolesMutation.isPending}
              onClick={() => rolesMutation.mutate()}
              className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--text)", color: "var(--bg)" }}
            >
              {rolesMutation.isPending ? i18n("loading33ce417") : i18n("saveRoles")}
            </button>
            <button
              type="button"
              onClick={() => setDraft(null)}
              className="rounded-full px-4 py-2 text-sm font-semibold"
              style={{ background: "var(--bg-soft)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
            >
              {i18n("cancel77dfd21")}
            </button>
          </div>
        ) : null}
        {rolesMutation.isError ? (
          <p role="alert" className="mt-2 text-sm" style={{ color: "var(--danger)" }}>
            {localizeError(rolesMutation.error, i18n)}
          </p>
        ) : null}
      </div>

      {showHeadCoach ? (
        <label className="flex items-start gap-3 rounded-2xl p-4" style={{ background: "var(--bg-soft)", border: "1px solid var(--border)" }}>
          <input
            type="checkbox"
            className="mt-1"
            checked={headCoach}
            disabled={scopeMutation.isPending}
            onChange={(event) => scopeMutation.mutate(event.target.checked ? "all" : "own")}
          />
          <span>
            <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>{i18n("headCoach")}</span>
            <span className="block text-xs" style={{ color: "var(--dim)" }}>{i18n("headCoachHelp")}</span>
          </span>
        </label>
      ) : null}
    </div>
  );
}
