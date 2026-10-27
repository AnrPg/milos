"use client";

import { usePathname, useRouter } from "next/navigation";
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { fetchGuideProgress, guideProgressKey, putGuideProgress, type GuideProgress, type GuideProgressList, type GuideStatus } from "@/api/guides";
import { gymClubFor } from "@/components/community/community";
import { useMyClubs } from "@/components/community/use-community";
import { useEventHosts } from "@/components/events/HostedEventSheet";
import { useSession } from "@/components/session-provider";
import { onRoute, readRun, resolveRoute, routeHref, startRoute, stripOrganization, resumeIndex, visibleSteps, writeRun, type GuideRun, type RouteParams } from "@/lib/guides/engine";
import { GUIDES, guideById, isGuideId } from "@/lib/guides/registry";
import type { Guide, GuideAbilities, GuideId, GuideStep } from "@/lib/guides/types";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { useOrganizationSlug } from "@/lib/organization-slug";
import { hasStaffRole } from "@/lib/role-navigation";

type GuideContextValue = {
  abilities: GuideAbilities;
  routeParams: RouteParams;
  /** Stored progress, by guide; undefined while loading. */
  progress: GuideProgress[] | undefined;
  progressError: boolean;
  /** The running guide, its visible steps and the step shown. */
  active: { guide: Guide; steps: GuideStep[]; index: number } | null;
  start: (id: GuideId, options?: { resume?: boolean }) => void;
  goTo: (index: number) => void;
  finish: () => void;
  dismiss: (id?: GuideId) => void;
};

const GuideContext = createContext<GuideContextValue | null>(null);

/**
 * ADR-193: one provider in the root layout runs at most one walkthrough at a
 * time. The run (guide and step) is kept for the tab, so it survives the
 * page changes a guide makes; progress goes to the account, so it is the
 * same on every device. Telemetry is the API's (`[:palee, :guides, …]`).
 */
export function GuideProvider({ children }: { children: ReactNode }) {
  const { tokens, status } = useSession();
  const token = tokens?.access_token ?? null;
  const signedIn = status === "authenticated" && Boolean(token);
  const queryClient = useQueryClient();
  const pathname = usePathname() ?? "/";
  const router = useRouter();
  const organizationSlug = useOrganizationSlug();
  const [run, setRun] = useState<GuideRun | null>(null);
  // What a person may see is read only where guides show: during a run, on
  // the guides list and on a guide's home (the first-visit offer).
  const needed = signedIn && (run !== null || stripOrganization(pathname) === "/guides" || GUIDES.some((guide) => onRoute({ path: guide.home.path }, pathname, "")));
  const abilities = useAbilities(needed);
  const clubs = useMyClubs(needed);
  const { membership } = useSelectedMembershipRole();
  const gymClub = gymClubFor(clubs.data ?? [], membership?.organization?.id);
  const routeParams = useMemo<RouteParams>(() => ({ gymClub: gymClub?.id ?? null }), [gymClub?.id]);

  const progressQuery = useQuery({
    queryKey: guideProgressKey(),
    enabled: needed,
    queryFn: () => fetchGuideProgress(token!),
    staleTime: 5 * 60_000,
  });

  const save = useMutation({
    mutationFn: ({ id, ...body }: { id: GuideId; status: GuideStatus; step: number; version: number }) => putGuideProgress(token!, id, body),
    onSuccess: (row) =>
      queryClient.setQueryData<GuideProgressList>(guideProgressKey(), (current) => ({
        guides: [...(current?.guides ?? []).filter((entry) => entry.guide_id !== row.guide_id), row],
      })),
  });
  const record = useRef(save.mutate);
  useEffect(() => {
    record.current = save.mutate;
  });

  // The run of this tab comes back after a reload (read once on mount, not during render).
  useEffect(() => {
    const stored = readRun(isGuideId);
    if (stored) queueMicrotask(() => setRun(stored));
  }, []);

  const update = useCallback((next: GuideRun | null) => {
    writeRun(next);
    setRun(next);
  }, []);

  const active = useMemo(() => {
    if (!run || !signedIn) return null;
    const guide = guideById(run.guide);
    const steps = visibleSteps(guide, abilities);
    if (steps.length === 0) return null;
    return { guide, steps, index: Math.min(run.index, steps.length - 1) };
  }, [abilities, run, signedIn]);

  const send = useCallback(
    (guide: Guide, statusValue: GuideStatus, step: number) => {
      if (!token) return;
      record.current({ id: guide.id, status: statusValue, step: Math.min(step, 99), version: guide.version });
    },
    [token],
  );

  const start = useCallback(
    (id: GuideId, options: { resume?: boolean } = {}) => {
      const guide = guideById(id);
      const steps = visibleSteps(guide, abilities);
      const stored = progressQuery.data?.guides.find((row) => row.guide_id === id);
      const index = options.resume ? resumeIndex(guide, stored, steps) : 0;
      const route = resolveRoute(startRoute(guide, steps, index), routeParams) ?? guide.home;
      if (!onRoute(route, window.location.pathname, window.location.search)) router.push(routeHref(route, organizationSlug));
      update({ guide: id, index });
      send(guide, "started", index);
    },
    [abilities, organizationSlug, progressQuery.data, routeParams, router, send, update],
  );

  const goTo = useCallback(
    (index: number) => {
      if (!active) return;
      const next = Math.max(0, Math.min(index, active.steps.length - 1));
      update({ guide: active.guide.id, index: next });
      send(active.guide, "started", next);
    },
    [active, send, update],
  );

  const finish = useCallback(() => {
    if (!active) return;
    send(active.guide, "completed", active.index);
    update(null);
  }, [active, send, update]);

  const dismiss = useCallback(
    (id?: GuideId) => {
      const guide = id ? guideById(id) : active?.guide;
      if (!guide) return;
      const step = active && active.guide.id === guide.id ? active.index : 0;
      send(guide, "dismissed", step);
      if (active && active.guide.id === guide.id) update(null);
    },
    [active, send, update],
  );

  const value = useMemo<GuideContextValue>(
    () => ({
      abilities,
      routeParams,
      progress: progressQuery.data?.guides,
      progressError: progressQuery.isError,
      active,
      start,
      goTo,
      finish,
      dismiss,
    }),
    [abilities, active, dismiss, finish, goTo, progressQuery.data, progressQuery.isError, routeParams, start],
  );

  return <GuideContext.Provider value={value}>{children}</GuideContext.Provider>;
}

export function useGuides() {
  const value = useContext(GuideContext);
  if (!value) throw new Error("missing-guide-provider");
  return value;
}

/** The same, or null outside the provider (screens rendered alone in tests). */
export function useOptionalGuides() {
  return useContext(GuideContext);
}

function useAbilities(needed: boolean): GuideAbilities {
  const { membership } = useSelectedMembershipRole();
  const clubs = useMyClubs(needed);
  const hosts = useEventHosts(needed);
  const roles = membership?.roles ?? [];
  const staff = hasStaffRole(membership);
  const manager = roles.includes("owner") || roles.includes("admin");
  const demo = membership?.organization?.activation === "demo";
  const hostsEvents = (hosts.data ?? []).some((host) => Boolean(host.organization_id && host.slug));
  const inGymClub = (clubs.data ?? []).some((club) => club.kind === "gym");
  return useMemo(
    () => ({ staff, manager, demo, hosts: hostsEvents, inGymClub }),
    [demo, hostsEvents, inGymClub, manager, staff],
  );
}
