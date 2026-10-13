"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";

import { endCoachingRelationship, fetchCoachingRelationships, startCoachingRelationship } from "@/api/roles";
import { fetchGymStaff } from "@/api/staff";
import { coachOptions, roleErrorKey } from "@/components/admin/staff-home";
import { formatDateTime } from "@/components/client/format";
import { useSession } from "@/components/session-provider";
import {
  dangerButtonStyle,
  inputClass,
  inputStyle,
  secondaryButtonClass,
  primaryButtonStyle,
  StatusText,
} from "@/components/staff/staff-ui";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";

// A client's coaches (ADR-100): owners and admins assign and end them.

const ORIGIN_KEYS = { assigned: "rhOriginAssigned", self_assigned: "rhOriginSelfAssigned", invited: "rhOriginInvited" } as const;

export function CoachAssignmentPanel({ userId }: { userId: string }) {
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const queryClient = useQueryClient();
  const { membership } = useSelectedMembershipRole();
  const canAssign = can(membership, "assign_coaches");
  const [coachId, setCoachId] = useState("");
  const key = ["staff", "coaching-relationships", { client: userId }];

  const relationships = useQuery({
    queryKey: key,
    enabled: Boolean(token),
    queryFn: () => fetchCoachingRelationships(token!, { clientUserId: userId }),
  });
  const staff = useQuery({
    queryKey: ["staff", "members"],
    enabled: Boolean(token) && canAssign,
    queryFn: () => fetchGymStaff(token!),
    staleTime: 60_000,
  });
  const refresh = () => queryClient.invalidateQueries({ queryKey: ["staff", "coaching-relationships"] });
  const assign = useMutation({
    mutationFn: () => startCoachingRelationship(token!, userId, coachId),
    onSuccess: async () => {
      setCoachId("");
      await refresh();
    },
  });
  const end = useMutation({ mutationFn: (id: string) => endCoachingRelationship(token!, id), onSuccess: refresh });

  const current = relationships.data ?? [];
  const currentCoachIds = new Set(current.map((item) => item.coach_user_id));
  const options = coachOptions(staff.data ?? []).filter((coach) => !currentCoachIds.has(coach.user_id));
  const failed = assign.isError ? assign.error : end.isError ? end.error : null;
  const errorText = (error: unknown) => {
    const errorKey = roleErrorKey(error);
    return errorKey ? i18n(errorKey) : localizeError(error, i18n);
  };

  return (
    <div className="space-y-3">
      {relationships.isPending ? (
        <StatusText tone="muted">{i18n("loading33ce417")}</StatusText>
      ) : relationships.isError ? (
        <StatusText tone="error">{errorText(relationships.error)}</StatusText>
      ) : current.length === 0 ? (
        <StatusText tone="muted">{i18n("rhNoCoaches")}</StatusText>
      ) : (
        <ul className="grid gap-2">
          {current.map((item) => (
            <li
              key={item.id}
              className="flex flex-wrap items-center justify-between gap-3 rounded-[1.2rem] px-4 py-3"
              style={{ background: "var(--bg-soft)", border: "1px solid var(--border)" }}
            >
              <span className="min-w-0">
                <span className="block truncate font-semibold" style={{ color: "var(--text)" }}>
                  {item.coach_nickname ?? i18n("stfCoach")}
                </span>
                <span className="block text-xs" style={{ color: "var(--dim)" }}>
                  {i18n(ORIGIN_KEYS[item.origin])}
                  {item.started_at ? ` · ${i18n("rhSince", { time: formatDateTime(item.started_at, locale) })}` : ""}
                </span>
              </span>
              {canAssign ? (
                <button
                  type="button"
                  disabled={end.isPending}
                  className={secondaryButtonClass}
                  style={dangerButtonStyle}
                  onClick={() => {
                    if (window.confirm(i18n("rhEndCoachingConfirm"))) end.mutate(item.id);
                  }}
                >
                  {i18n("rhEndCoaching")}
                </button>
              ) : null}
            </li>
          ))}
        </ul>
      )}

      {canAssign ? (
        <form
          className="flex flex-col gap-2 sm:flex-row"
          onSubmit={(event) => {
            event.preventDefault();
            if (coachId) assign.mutate();
          }}
        >
          <select
            aria-label={i18n("rhAssignCoach")}
            className={`${inputClass} sm:flex-1`}
            style={inputStyle}
            value={coachId}
            onChange={(event) => setCoachId(event.target.value)}
          >
            <option value="">{options.length ? i18n("rhChooseCoach") : i18n("rhNoCoachesToAssign")}</option>
            {options.map((coach) => (
              <option key={coach.user_id} value={coach.user_id}>
                {coach.nickname ?? coach.user_id}
              </option>
            ))}
          </select>
          <button type="submit" disabled={!coachId || assign.isPending} className={secondaryButtonClass} style={primaryButtonStyle}>
            {i18n("rhAssignCoach")}
          </button>
        </form>
      ) : null}

      {failed ? <StatusText tone="error">{errorText(failed)}</StatusText> : null}
    </div>
  );
}
