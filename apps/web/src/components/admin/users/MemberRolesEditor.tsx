"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
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
import { ChangedMark } from "@/components/ui/ChangedMark";
import { useDraftForm } from "@/components/ui/DraftForms";

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
  const currentHeadCoach = membership?.coach_scope === "all";
  // A branch manager hands out their own branches, never «every branch».
  const presetScope = actorScope !== "all" && currentScope === "all" && !hasScopedStaffRole(current) ? actorScope : currentScope;

  const locations = useQuery({
    queryKey: ["admin", "locations"],
    enabled: grantable.length > 0 && !self,
    queryFn: () => listAdminLocations(token),
  });

  // ADR-276: roles, branches and the head coach switch are one draft, saved
  // with the profile's «Αποθήκευση» bar.
  const form = useDraftForm<RolesDraft>({
    server: { roles: canonicalRoles(current), scope: presetScope, head_coach: currentHeadCoach },
    testId: "roles-save-bar",
    // The scope goes first: a branch manager may give a staff role only to
    // someone who already works inside their branches.
    save: async (draft) => {
      if (draft.roles.length === 0) throw new RolesInvalid("chooseOneRole");
      if (!self && hasScopedStaffRole(draft.roles) && draft.scope !== "all" && draft.scope.length === 0) throw new RolesInvalid("chooseOneBranch");
      if (!self && hasScopedStaffRole(draft.roles) && !sameScope(draft.scope, currentScope)) {
        await updateLocationScope(token, userId, draft.scope === "all" ? null : draft.scope);
      }
      if (draft.roles.join() !== canonicalRoles(current).join()) await updateMemberRoles(token, userId, draft.roles);
      if (draft.head_coach !== currentHeadCoach) await updateCoachScope(token, userId, draft.head_coach ? "all" : "own");
    },
    describeError: (error) => (error instanceof RolesInvalid ? t(error.key) : localizeError(error, i18n)),
    onSaved: () => queryClient.invalidateQueries({ queryKey: ["admin", "users"] }),
  });
  const roles = form.draft.roles;
  const scope = form.draft.scope;
  const scoped = !self && hasScopedStaffRole(roles);
  const showBranches =
    scoped && (hasSeveralBranches(locations.data) || actorScope !== "all" || currentScope !== "all");
  const branchManagerPreset =
    !self && actorRoles.includes("owner") && hasSeveralBranches(locations.data) && !roles.includes("owner");

  if (!membership || grantable.length === 0) return null;

  const toggle = (role: RoleName) => {
    const next = canonicalRoles(roles.includes(role) ? roles.filter((item) => item !== role) : [...roles, role]);
    // Dropping the last staff role puts the branches back as they were.
    form.edit(hasScopedStaffRole(next) ? { roles: next } : { roles: next, scope: presetScope });
  };
  const applyBranchManager = () =>
    form.edit({ roles: canonicalRoles(roles.includes("admin") ? roles : [...roles, "admin"]), ...(scope === "all" ? { scope: [] } : {}) });
  const showHeadCoach =
    current.includes("coach") && can(actor, "set_head_coach") && (self || canManageMember(actorRoles, current));
  const visible = ALL_ROLES.filter((role) => grantable.includes(role) || current.includes(role));

  return (
    <div className="space-y-4">
      <div>
        <span className="flex flex-wrap items-center gap-2 text-xs uppercase tracking-wider" style={{ color: "var(--muted)" }}>
          {i18n("rolesInThisGym")}
          {form.changed.has("roles") || (scoped && form.changed.has("scope")) ? <ChangedMark /> : null}
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
                disabled={locked || form.saving}
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
            disabled={form.saving}
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
          disabled={form.saving}
          onChange={(next) => form.edit({ scope: next })}
        />
      ) : null}

      {roles.length === 0 ? <ErrorNotice variant="field">{t("chooseOneRole")}</ErrorNotice> : null}

      {showHeadCoach ? (
        <label className="flex items-start gap-3 rounded-2xl p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
          <input
            type="checkbox"
            className="mt-1"
            checked={form.draft.head_coach}
            disabled={form.saving}
            onChange={(event) => form.edit({ head_coach: event.target.checked })}
          />
          <span>
            <span className="flex flex-wrap items-center gap-2 text-sm font-semibold" style={{ color: "var(--text)" }}>{i18n("headCoach")}{form.changed.has("head_coach") ? <ChangedMark /> : null}</span>
            <span className="block text-xs" style={{ color: "var(--dim)" }}>{i18n("headCoachHelp")}</span>
          </span>
        </label>
      ) : null}
      {form.bar}
    </div>
  );
}

/** A draft the API would refuse: the bar names what is missing. */
class RolesInvalid extends Error {
  key: "chooseOneRole" | "chooseOneBranch";
  constructor(key: "chooseOneRole" | "chooseOneBranch") {
    super(key);
    this.key = key;
  }
}

type RolesDraft = { roles: RoleName[]; scope: LocationScope; head_coach: boolean };

/** Roles in one fixed order, so toggling a role off and on is no change. */
function canonicalRoles(roles: RoleName[]) {
  return ALL_ROLES.filter((role) => roles.includes(role));
}
