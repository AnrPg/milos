"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { listAdminLocations } from "@/api/facility";
import { ALL_ROLES, updateCoachScope, updateLocationScope, updateMemberRoles, type RoleName } from "@/api/roles";
import { useSession } from "@/components/session-provider";
import { localizeError } from "@/i18n/presentation";
import { RoleLabel } from "@/components/semantic-label";
import { BranchScopePicker } from "@/components/admin/users/BranchScopePicker";
import {
  hasSeveralBranches,
  membershipLocationScope,
  sameScope,
  toLocationScope,
  type LocationScope,
  type LocationScopePayload,
} from "@/lib/location-scope";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can, membershipRoles } from "@/lib/role-navigation";
import { canManageMember, editableRoles } from "@/lib/role-hierarchy";
import { useUiTranslations } from "@/i18n/ui";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

const STAFF: RoleName[] = ["owner", "admin", "coach", "front_desk", "accountant", "janitor"];

/** Staff roles below owner carry a branch scope (ADR-186). */
export function hasScopedStaffRole(roles: string[]) {
  return !roles.includes("owner") && roles.some((role) => STAFF.includes(role as RoleName));
}

/**
 * Roles held together in this gym, the head coach switch (ADR-099, ADR-100)
 * and the branches the person works at (ADR-186). Only people ranked below
 * the signed-in person are editable; on one's own profile only roles below
 * one's top role move, and the branches stay as they are (ADR-219).
 */
export function MemberRolesEditor({
  token,
  userId,
  membership,
}: {
  token: string;
  userId: string;
  membership: { roles: string[]; coach_scope: string; location_scope?: LocationScopePayload | null } | null | undefined;
}) {
  const i18n = useUiTranslations();
  const t = useTranslations("BranchScope");
  const queryClient = useQueryClient();
  const { currentUser } = useSession();
  const { membership: actor } = useSelectedMembershipRole();
  const actorRoles = membershipRoles(actor);
  const actorScope = membershipLocationScope(actor);
  const current = (membership?.roles ?? []) as RoleName[];
  const self = currentUser?.id === userId;
  const grantable = editableRoles(actorRoles, current, self);
  const currentScope = toLocationScope(membership?.location_scope);
  const [draft, setDraft] = useState<RoleName[] | null>(null);
  const [scopeDraft, setScopeDraft] = useState<LocationScope | null>(null);
  const roles = draft ?? current;
  // A branch manager hands out their own branches, never «every branch».
  const fromActor = actorScope !== "all" && currentScope === "all" && !hasScopedStaffRole(current);
  const scope = scopeDraft ?? (fromActor ? actorScope : currentScope);
  const rolesChanged = draft !== null && [...draft].sort().join() !== [...current].sort().join();
  const scoped = !self && hasScopedStaffRole(roles);
  const scopeChanged = scoped && !sameScope(scope, currentScope);
  const changed = rolesChanged || scopeChanged;

  const locations = useQuery({
    queryKey: ["admin", "locations"],
    enabled: grantable.length > 0 && !self,
    queryFn: () => listAdminLocations(token),
  });
  const showBranches =
    scoped && (hasSeveralBranches(locations.data) || actorScope !== "all" || currentScope !== "all");
  const branchManagerPreset =
    !self && actorRoles.includes("owner") && hasSeveralBranches(locations.data) && !roles.includes("owner");

  const refresh = () => queryClient.invalidateQueries({ queryKey: ["admin", "users"] });
  const saveMutation = useMutation({
    // The scope goes first: a branch manager may give a staff role only to
    // someone who already works inside their branches.
    mutationFn: async () => {
      if (scopeChanged) await updateLocationScope(token, userId, scope === "all" ? null : scope);
      if (rolesChanged) await updateMemberRoles(token, userId, roles);
    },
    onSuccess: async () => {
      setDraft(null);
      setScopeDraft(null);
      await refresh();
    },
  });
  const coachScopeMutation = useMutation({
    mutationFn: (value: "own" | "all") => updateCoachScope(token, userId, value),
    onSuccess: refresh,
  });

  if (!membership || grantable.length === 0) return null;

  const toggle = (role: RoleName) =>
    setDraft(roles.includes(role) ? roles.filter((item) => item !== role) : [...roles, role]);
  const applyBranchManager = () => {
    setDraft(roles.includes("admin") ? roles : [...roles, "admin"]);
    if (scope === "all") setScopeDraft([]);
  };
  const headCoach = membership.coach_scope === "all";
  const showHeadCoach =
    current.includes("coach") && can(actor, "set_head_coach") && (self || canManageMember(actorRoles, current));
  const visible = ALL_ROLES.filter((role) => grantable.includes(role) || current.includes(role));
  const invalidScope = showBranches && scope !== "all" && scope.length === 0;

  return (
    <div className="space-y-4">
      <div>
        <span className="block text-xs uppercase tracking-wider" style={{ color: "var(--muted)" }}>
          {i18n("rolesInThisGym")}
        </span>
        <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
          {i18n(self ? "myRolesHelp" : "rolesInThisGymHelp")}
        </p>
        <div className="mt-2 flex flex-wrap gap-2">
          {visible.map((role) => {
            const selected = roles.includes(role);
            const locked = !grantable.includes(role);
            return (
              <button
                key={role}
                type="button"
                aria-pressed={selected}
                disabled={locked || saveMutation.isPending}
                onClick={() => toggle(role)}
                className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-60"
                style={{
                  background: selected ? "var(--primary)" : "var(--panel-muted)",
                  border: `1px ${STAFF.includes(role) ? "solid" : "dashed"} var(--border)`,
                  color: selected ? "var(--primary-contrast)" : "var(--text-soft)",
                }}
              >
                <RoleLabel role={role} />
              </button>
            );
          })}
        </div>
        {branchManagerPreset ? (
          <button
            type="button"
            disabled={saveMutation.isPending}
            onClick={applyBranchManager}
            className="mt-3 rounded-2xl px-4 py-3 text-start disabled:opacity-60"
            style={{ background: "var(--panel-muted)", border: "1px dashed var(--border)" }}
          >
            <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>{t("branchManager")}</span>
            <span className="block text-xs" style={{ color: "var(--dim)" }}>{t("branchManagerHelp")}</span>
          </button>
        ) : null}
      </div>

      {showBranches ? (
        <BranchScopePicker
          locations={locations.data ?? []}
          value={scope}
          allowed={actorScope}
          disabled={saveMutation.isPending}
          onChange={setScopeDraft}
        />
      ) : null}

      {changed ? (
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            disabled={roles.length === 0 || invalidScope || saveMutation.isPending}
            onClick={() => saveMutation.mutate()}
            className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
            style={{ background: "var(--text)", color: "var(--bg)" }}
          >
            {saveMutation.isPending ? i18n("loading33ce417") : i18n("saveRoles")}
          </button>
          <button
            type="button"
            onClick={() => {
              setDraft(null);
              setScopeDraft(null);
            }}
            className="rounded-full px-4 py-2 text-sm font-semibold"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
          >
            {i18n("cancel77dfd21")}
          </button>
        </div>
      ) : null}
      {saveMutation.isError ? (
        <ErrorNotice>
          {localizeError(saveMutation.error, i18n)}
        </ErrorNotice>
      ) : null}

      {showHeadCoach ? (
        <label className="flex items-start gap-3 rounded-2xl p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
          <input
            type="checkbox"
            className="mt-1"
            checked={headCoach}
            disabled={coachScopeMutation.isPending}
            onChange={(event) => coachScopeMutation.mutate(event.target.checked ? "all" : "own")}
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
