"use client";





import {useUiTranslations} from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";

import { ApiError } from "@/api/client";
import {
  createWorkoutFolder,
  deleteWorkoutFolder,
  deleteWorkout,
  listWorkoutFolders,
  listAdminWorkouts,
  moveWorkoutToFolder,
  updateWorkoutFolder,
  type WorkoutFolder,
  type WorkoutRecord,
} from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { HoverHint } from "@/components/HelpTooltip";
import { TransientHero } from "@/components/TransientHero";
import { USER_SYNC_EVENT, type UserSyncDetail } from "@/lib/user-sync";
import { AssignWorkoutPanel } from "@/components/workouts/AssignWorkoutPanel";
import { WorkoutEditModal } from "@/components/workouts/WorkoutEditModal";
import { WorkoutPreviewDetail } from "@/components/workouts/WorkoutPreviewDetail";
import { SemanticLabel } from "@/components/semantic-label";
import { ShareExportDialog } from "@/components/share-export/ShareExportDialog";
import { useShareExport } from "@/components/share-export/useShareExport";
import { buildWorkoutDocument } from "@/lib/document-export";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

type LibraryViewMode = "folders" | "tiles" | "list";

const LIBRARY_VIEW_MODES: readonly LibraryViewMode[] = ["folders", "tiles", "list"];
const LIBRARY_VIEW_ICONS: Record<LibraryViewMode, string> = { folders: "📁", tiles: "▦", list: "☰" };

export function WorkoutAdminConsole() {
  const i18n = useUiTranslations();
  const shareExport = useShareExport();
  const router = useRouter();
  const organizationSlug = useOrganizationSlug();
  const { currentUser, signOut, status, tokens } = useSession();
  const { role } = useSelectedMembershipRole();
  const [workouts, setWorkouts] = useState<WorkoutRecord[]>([]);
  const [folders, setFolders] = useState<WorkoutFolder[]>([]);
  const [viewMode, setViewMode] = useState<LibraryViewMode>("folders");
  const [selectedFolderId, setSelectedFolderId] = useState<string | null | "all">("all");
  const sortKey = "title" as const;
  const [folderName, setFolderName] = useState("");
  const [folderParentId, setFolderParentId] = useState<string>("");
  const [folderModalOpen, setFolderModalOpen] = useState(false);
  const [viewMenuOpen, setViewMenuOpen] = useState(false);
  const viewMenuRef = useRef<HTMLDivElement>(null);
  const [collapsedFolderIds, setCollapsedFolderIds] = useState<Set<string>>(() => new Set());
  const [moveMenuWorkoutId, setMoveMenuWorkoutId] = useState<string | null>(null);
  const [draggedWorkoutId, setDraggedWorkoutId] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busyAction, setBusyAction] = useState<string | null>(null);
  const [editTarget, setEditTarget] = useState<WorkoutRecord | null>(null);
  const [assignTarget, setAssignTarget] = useState<WorkoutRecord | null>(null);
  const [previewWorkoutId, setPreviewWorkoutId] = useState<string | null>(null);
  const [shareTarget, setShareTarget] = useState<WorkoutRecord | null>(null);

  function clearAdminData() {
    setWorkouts([]);
  }

  const reloadAdminData = useCallback(async () => {
    if (status !== "authenticated" || !tokens?.access_token || !currentUser) return;
    if (role !== "admin") return;

    try {
      const [workoutList, folderList] = await Promise.all([
        listAdminWorkouts(tokens.access_token),
        listWorkoutFolders(tokens.access_token),
      ]);
      setWorkouts(workoutList);
      setFolders(folderList);
      setMessage(null);
      setError(null);
    } catch (loadError) {
      if (loadError instanceof ApiError && (loadError.status === 401 || loadError.status === 403)) {
        clearAdminData();
        signOut();
        router.replace(`/login?next=${encodeURIComponent(adminHref("/admin/workouts", organizationSlug))}`);
        return;
      }

      setError(loadError instanceof Error ? localizeError(loadError, i18n) : i18n("failedToLoadAdminWorkoutData3641095"));
    }
  }, [currentUser, i18n, organizationSlug, role, router, signOut, status, tokens]);

  useEffect(() => {
    queueMicrotask(() => {
      void reloadAdminData();
    });
  }, [reloadAdminData]);

  useEffect(() => {
    if (!previewWorkoutId) return;
    function handleKey(e: KeyboardEvent) {
      if (e.key === "Escape") setPreviewWorkoutId(null);
    }
    window.addEventListener("keydown", handleKey);
    return () => window.removeEventListener("keydown", handleKey);
  }, [previewWorkoutId]);

  useEffect(() => {
    if (!viewMenuOpen) return;
    function handlePointerDown(event: PointerEvent) {
      if (!viewMenuRef.current?.contains(event.target as Node)) setViewMenuOpen(false);
    }
    function handleKey(event: KeyboardEvent) {
      if (event.key === "Escape") setViewMenuOpen(false);
    }
    document.addEventListener("pointerdown", handlePointerDown);
    document.addEventListener("keydown", handleKey);
    return () => {
      document.removeEventListener("pointerdown", handlePointerDown);
      document.removeEventListener("keydown", handleKey);
    };
  }, [viewMenuOpen]);

  useEffect(() => {
    function handleUserSync(event: Event) {
      const detail = (event as CustomEvent<UserSyncDetail>).detail;

      if (!detail?.scopes.includes("admin_workouts")) {
        return;
      }

      void reloadAdminData();
    }

    window.addEventListener(USER_SYNC_EVENT, handleUserSync as EventListener);

    return () => {
      window.removeEventListener(USER_SYNC_EVENT, handleUserSync as EventListener);
    };
  }, [reloadAdminData]);

  async function runAction(action: string, effect: () => Promise<void>) {
    setBusyAction(action);
    setError(null);
    setMessage(null);

    try {
      await effect();
    } catch (actionError) {
      if (actionError instanceof ApiError) {
        if (actionError.status === 401 || actionError.status === 403) {
          signOut();
          router.replace(`/login?next=${encodeURIComponent(adminHref("/admin/workouts", organizationSlug))}`);
          return;
        }

        setError(localizeError(actionError, i18n));
      } else {
        setError(actionError instanceof Error ? localizeError(actionError, i18n) : i18n("unexpectedRequestFailurea7ffd06"));
      }
    } finally {
      setBusyAction(null);
    }
  }

  async function handleDeleteWorkout(workout: WorkoutRecord) {
    if (!tokens?.access_token) return;

    const confirmed = window.confirm(
      i18n("delete63346e8") + (workout.title || i18n("thisWorkoutd8375a8")) + i18n("permanentlyThisHardDeleteRemovesTheWorkoutDefinitionbb6e054"),
    );

    if (!confirmed) return;

    await runAction("delete-" + (workout.id), async () => {
      await deleteWorkout(tokens.access_token, workout.id);
      setWorkouts((current) => current.filter((item) => item.id !== workout.id));
      setMessage(i18n("deleted98c055d") + (workout.title || "workout") + "\".");
    });
  }

  const folderById = new Map(folders.map((folder) => [folder.id, folder]));
  const currentFolder = typeof selectedFolderId === "string" && selectedFolderId !== "all" ? folderById.get(selectedFolderId) : undefined;
  const folderLabel = (folder: WorkoutFolder) => {
    const parts = [folder.name];
    let parent = folder.parent_id ? folderById.get(folder.parent_id) : undefined;
    while (parent) {
      parts.unshift(parent.name);
      parent = parent.parent_id ? folderById.get(parent.parent_id) : undefined;
    }
    return parts.join(" / ");
  };
  const folderPath = (() => {
    if (!currentFolder) return [];
    const parts: WorkoutFolder[] = [];
    let node: WorkoutFolder | undefined = currentFolder;
    while (node) {
      parts.unshift(node);
      node = node.parent_id ? folderById.get(node.parent_id) : undefined;
    }
    return parts;
  })();
  const orderedFolders = [...folders].sort((a, b) => folderLabel(a).localeCompare(folderLabel(b)));
  const viewModeLabelFor = (mode: LibraryViewMode) => i18n(`featureView${mode[0].toUpperCase()}${mode.slice(1)}`);
  const viewModeLabel = viewModeLabelFor(viewMode);
  // Every view is rooted at the folder picked in the path; folder view shows one level,
  // tiles and list views show the whole subtree as collapsible groups.
  const treeRootId = selectedFolderId === "all" ? null : selectedFolderId;
  const childFolders = (parentId: string | null) =>
    orderedFolders.filter((folder) => (folder.parent_id ?? null) === parentId);
  const folderWorkouts = (folderId: string | null) =>
    workouts
      .filter((workout) => (workout.folder_id ?? null) === folderId)
      .sort((a, b) => String(a[sortKey] ?? "").localeCompare(String(b[sortKey] ?? "")));
  const subtreeWorkoutCount = (folderId: string): number =>
    folderWorkouts(folderId).length + childFolders(folderId).reduce((total, child) => total + subtreeWorkoutCount(child.id), 0);
  const visibleFolders = childFolders(treeRootId);
  const visibleWorkouts = folderWorkouts(treeRootId);
  const toggleFolderGroup = (folderId: string) => {
    setCollapsedFolderIds((current) => {
      const next = new Set(current);
      if (next.has(folderId)) next.delete(folderId);
      else next.add(folderId);
      return next;
    });
  };

  async function addFolder() {
    if (!tokens?.access_token || !folderName.trim()) return;
    await runAction("create-folder", async () => {
      const folder = await createWorkoutFolder(tokens.access_token!, {
        name: folderName.trim(),
        parent_id: folderParentId || null,
      });
      setFolders((current) => [...current, folder]);
      setFolderName("");
      setFolderModalOpen(false);
    });
  }

  async function moveDraggedWorkout(folderId: string | null) {
    if (!tokens?.access_token || !draggedWorkoutId) return;
    const workoutId = draggedWorkoutId;
    setDraggedWorkoutId(null);
    await runAction(`move-${workoutId}`, async () => {
      await moveWorkoutToFolder(tokens.access_token!, workoutId, folderId);
      setWorkouts((current) => current.map((item) => item.id === workoutId ? { ...item, folder_id: folderId } : item));
    });
  }

  async function renameFolder(folder: WorkoutFolder) {
    if (!tokens?.access_token) return;
    const name = window.prompt(i18n("featureFolderName"), folder.name)?.trim();
    if (!name) return;
    await runAction(`folder-${folder.id}`, async () => {
      const updated = await updateWorkoutFolder(tokens.access_token!, folder.id, {
        name,
        parent_id: folder.parent_id,
      });
      setFolders((current) => current.map((item) => item.id === updated.id ? updated : item));
    });
  }

  async function removeFolder(folder: WorkoutFolder) {
    if (!tokens?.access_token || !window.confirm(
      i18n("featureDeleteFolderConfirm", { name: folder.name }),
    )) return;
    await runAction(`folder-${folder.id}`, async () => {
      await deleteWorkoutFolder(tokens.access_token!, folder.id);
      setFolders((current) => current.filter((item) => item.id !== folder.id).map((item) => item.parent_id === folder.id ? { ...item, parent_id: folder.parent_id } : item));
      setWorkouts((current) => current.map((item) => item.folder_id === folder.id ? { ...item, folder_id: folder.parent_id } : item));
    });
  }

  const iconButtonClass = "grid h-8 w-8 place-items-center rounded-full text-sm opacity-65 hover:opacity-100";
  const iconButtonStyle = { background: "var(--panel)", border: "1px solid var(--border)" };

  function folderDropProps(folderId: string | null) {
    return {
      onDragOver: (event: React.DragEvent) => {
        if (draggedWorkoutId) event.preventDefault();
      },
      onDrop: (event: React.DragEvent) => {
        event.preventDefault();
        event.stopPropagation();
        void moveDraggedWorkout(folderId);
      },
    };
  }

  function renderWorkoutTile(workout: WorkoutRecord) {
    return (
      <article
        key={workout.id}
        className="rounded-[1.5rem] p-5"
        draggable
        onDragStart={() => setDraggedWorkoutId(workout.id)}
        onDragEnd={() => setDraggedWorkoutId(null)}
        style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", cursor: viewMode === "folders" ? "grab" : "pointer" }}
        onClick={() => setPreviewWorkoutId(workout.id)}
      >
        <div className="flex items-start justify-between gap-4">
          <div>
            <div className="flex items-center gap-2">
              <p className="text-lg font-semibold" style={{ color: "var(--text)" }}>{workout.title || i18n("untitledWorkouta1885a5")}</p>
              {workout.status === "draft" ? (
                <span className="rounded-full px-2 py-1 text-[10px] font-semibold uppercase tracking-widest" style={{ background: "color-mix(in srgb, var(--warning) 12%, transparent)", color: "var(--warning)" }}>
                  {i18n("draft23d33e2")}
                </span>
              ) : null}
              {workout.is_team_workout ? (
                <span className="rounded-full px-2 py-1 text-[10px] font-semibold uppercase tracking-widest" style={{ background: "color-mix(in srgb, var(--warning) 12%, transparent)", color: "var(--warning)", border: "1px solid color-mix(in srgb, var(--warning) 30%, transparent)" }}>
                  {i18n("team2188872")}
                </span>
              ) : null}
            </div>
            <p className="mt-1 text-sm uppercase tracking-[0.18em] text-[var(--primary)]"><SemanticLabel value={workout.type} /></p>
          </div>
          <div className="flex shrink-0 items-center gap-1" onClick={(event) => event.stopPropagation()}>
            <HoverHint hint={i18n("featureMoveToFolder")}>
              <button type="button" aria-label={i18n("featureMoveToFolder")} className={iconButtonClass} style={{ ...iconButtonStyle, color: "var(--text-soft)" }} onClick={() => setMoveMenuWorkoutId((id) => id === workout.id ? null : workout.id)}>↪</button>
            </HoverHint>
            {workout.status === "published" ? (
              <HoverHint hint={i18n("edit5301648")}>
                <button type="button" aria-label={i18n("edit5301648")} className={iconButtonClass} style={{ ...iconButtonStyle, color: "var(--text-soft)" }} onClick={() => setEditTarget(workout)}>✎</button>
              </HoverHint>
            ) : null}
            <HoverHint hint={shareExport.copy.title}>
              <button type="button" aria-label={shareExport.copy.title} className={iconButtonClass} style={{ ...iconButtonStyle, color: "var(--success)" }} onClick={() => setShareTarget(workout)}>⇪</button>
            </HoverHint>
            <HoverHint hint={i18n("deletef6fdbe4")} align="end">
              <button type="button" aria-label={i18n("deletef6fdbe4")} disabled={busyAction === `delete-${workout.id}`} className={`${iconButtonClass} disabled:opacity-30`} style={{ ...iconButtonStyle, color: "var(--danger)" }} onClick={() => void handleDeleteWorkout(workout)}>×</button>
            </HoverHint>
          </div>
        </div>

        <div className="mt-4 flex flex-wrap gap-2" onClick={(e) => e.stopPropagation()}>
          {moveMenuWorkoutId === workout.id ? <select aria-label={i18n("featureFolderForWorkout", { title: workout.title })} className="rounded-full px-3 py-1 text-xs" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} value={workout.folder_id ?? ""} onChange={(event) => {
            const folderId = event.target.value || null;
            if (!tokens?.access_token) return;
            void moveWorkoutToFolder(tokens.access_token, workout.id, folderId).then(() => {
              setWorkouts((current) => current.map((item) => item.id === workout.id ? { ...item, folder_id: folderId } : item));
              setMoveMenuWorkoutId(null);
            });
          }}>
            <option value="">{i18n("featureUncategorized")}</option>
            {orderedFolders.map((folder) => <option key={folder.id} value={folder.id}>{folderLabel(folder)}</option>)}
          </select> : null}
          {workout.status === "draft" ? (
            <Link
              className="rounded-full px-3 py-1 text-xs font-semibold"
              style={{ background: "var(--text)", color: "var(--bg)" }}
              href={adminHref(`/admin/workouts/new?draft=${workout.id}`, organizationSlug)}
              onClick={(e) => e.stopPropagation()}
            >
              {i18n("continueEditingb101465")}
            </Link>
          ) : null}

          {workout.status === "published" ? (
            <button
              className="rounded-full px-3 py-1 text-xs font-semibold"
              style={{ background: "var(--text)", color: "var(--bg)" }}
              onClick={(e) => { e.stopPropagation(); setAssignTarget(workout); }}
              type="button"
            >
              {i18n("featureAssignToAthleteOrClass")}
            </button>
          ) : null}

          {workout.available_scale_levels.length > 0 ? (
            workout.available_scale_levels.map((scaleLevel) => (
              <span
                key={(workout.id) + "-" + (scaleLevel.slug)}
                className="rounded-full px-3 py-1 text-xs font-semibold"
                style={{ background: "color-mix(in srgb, var(--primary) 12%, transparent)", color: "var(--primary)" }}
              >
                {scaleLevel.label}
              </span>
            ))
          ) : (
            <span className="rounded-full px-3 py-1 text-xs font-semibold" style={{ background: "var(--border)", color: "var(--dim)" }}>
              {i18n("baseOnly061c4ff")}
            </span>
          )}
        </div>

        <div className="mt-4 space-y-2 text-sm" style={{ color: "var(--muted)" }}>
          {(workout.sections ?? []).map((section) => (
            <div key={(workout.id) + "-" + (section.order)} className="flex items-center justify-between gap-4">
              <span>{section.name}</span>
              <span style={{ color: "var(--dim)" }}>{section.exercises.length} {i18n("exercises0ee6e81")}</span>
            </div>
          ))}
        </div>
      </article>
    );
  }

  function renderWorkoutRow(workout: WorkoutRecord) {
    return (
      <button
        key={workout.id}
        type="button"
        draggable
        onDragStart={() => setDraggedWorkoutId(workout.id)}
        onDragEnd={() => setDraggedWorkoutId(null)}
        className="grid w-full grid-cols-[minmax(0,1fr)_auto] items-center gap-4 border-b px-4 py-3 text-start last:border-b-0 hover:bg-[var(--panel-muted)]"
        style={{ borderColor: "var(--border)", color: "var(--text)" }}
        onClick={() => setPreviewWorkoutId(workout.id)}
      >
        <span className="min-w-0"><strong className="block truncate text-sm">{workout.title || i18n("untitledWorkouta1885a5")}</strong><span className="text-xs" style={{ color: "var(--muted)" }}><SemanticLabel value={workout.type} /></span></span>
        <span className="text-xs font-semibold" style={{ color: workout.status === "draft" ? "var(--warning)" : "var(--success)" }}><SemanticLabel value={workout.status ?? "published"} /></span>
      </button>
    );
  }

  function renderWorkoutCollection(items: WorkoutRecord[]) {
    if (items.length === 0) return null;
    if (viewMode === "list") {
      return (
        <div className="overflow-hidden rounded-lg" style={{ border: "1px solid var(--border)", background: "var(--panel)" }}>
          {items.map(renderWorkoutRow)}
        </div>
      );
    }
    return <div className="grid gap-4 lg:grid-cols-2">{items.map(renderWorkoutTile)}</div>;
  }

  function renderFolderGroup(folder: WorkoutFolder, depth: number): React.ReactNode {
    const collapsed = collapsedFolderIds.has(folder.id);
    const subfolders = childFolders(folder.id);
    const items = folderWorkouts(folder.id);
    return (
      <section
        key={folder.id}
        className="rounded-[1.2rem]"
        style={{ background: depth % 2 === 0 ? "var(--panel-muted)" : "var(--panel)", border: "1px solid var(--border)" }}
        {...folderDropProps(folder.id)}
      >
        <button
          type="button"
          aria-expanded={!collapsed}
          className="flex w-full items-center gap-2 px-4 py-3 text-start"
          onClick={() => toggleFolderGroup(folder.id)}
        >
          <span aria-hidden className="inline-block w-3 text-xs transition-transform" style={{ color: "var(--dim)", transform: collapsed ? "rotate(-90deg)" : undefined }}>▾</span>
          <span aria-hidden>📁</span>
          <span className="min-w-0 flex-1 truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{folder.name}</span>
          <span className="text-xs tabular-nums" style={{ color: "var(--muted)" }}>{subtreeWorkoutCount(folder.id)}</span>
        </button>
        {!collapsed ? (
          <div className="space-y-3 px-3 pb-3 sm:px-4 sm:pb-4">
            {renderWorkoutCollection(items)}
            {subfolders.map((child) => renderFolderGroup(child, depth + 1))}
            {items.length === 0 && subfolders.length === 0 ? (
              <p className="px-1 text-xs" style={{ color: "var(--dim)" }}>{i18n("featureEmptyFolder")}</p>
            ) : null}
          </div>
        ) : null}
      </section>
    );
  }

  return (
    <main className="min-h-screen px-6 py-8 md:px-10 md:py-12" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-7xl space-y-8">
        <TransientHero label={i18n("workoutManagementIntroduction675e60c")} timeoutMs={3000}>
        <section className="rounded-[2rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <div className="flex flex-wrap items-start justify-between gap-6">
            <div>
              <p className="text-sm font-semibold uppercase tracking-[0.28em] text-[var(--primary)]">{i18n("workoutsccb58b2")}</p>
              <h1 className="mt-2 max-w-3xl text-3xl font-semibold tracking-tight md:text-4xl" style={{ color: "var(--text)" }}>
                {i18n("workoutContentManagementb5ce5ce")}
              </h1>
              <p className="mt-4 max-w-3xl text-base leading-7" style={{ color: "var(--muted)" }}>
                {i18n("authorAndManageMasterWorkoutDefinitionsWorkoutsCan27f3d56")}
              </p>
            </div>
          </div>

        </section>
        </TransientHero>

        {!currentUser ? null : (
          <>
            {message ? (
              <section className="rounded-[1.8rem] px-5 py-4 text-sm font-semibold" style={{ background: "color-mix(in srgb, var(--success) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--success) 20%, transparent)", color: "var(--success)" }}>
                {message}
              </section>
            ) : null}

            {error ? (
              <section className="rounded-[1.8rem] px-5 py-4 text-sm" style={{ background: "color-mix(in srgb, var(--primary) 10%, transparent)", border: "1px solid color-mix(in srgb, var(--primary) 20%, transparent)", color: "var(--primary-strong)" }}>
                {error}
              </section>
            ) : null}

            <section className="rounded-[2rem] p-4 sm:p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
              <div className="flex items-center justify-between gap-4" aria-label={i18n("semanticWorkoutLibrary")}>
                <HoverHint hint={i18n("featureNewWorkoutHint")} align="start">
                  <Link
                    aria-label={i18n("newWorkout5fc6e4c")}
                    className="grid h-14 w-14 place-items-center rounded-2xl text-3xl transition-transform hover:-translate-y-0.5"
                    style={{ background: "var(--primary)", color: "var(--primary-contrast)", boxShadow: "0 12px 30px color-mix(in srgb, var(--primary) 35%, transparent)" }}
                    href={adminHref("/admin/workouts/new", organizationSlug)}
                  >
                    <span aria-hidden>🏋️</span>
                  </Link>
                </HoverHint>

                <div className="flex items-center gap-1">
                  <div ref={viewMenuRef} className="relative">
                    <HoverHint hint={i18n("featureViewMenuHint", { view: viewModeLabel })} align="end" suppressed={viewMenuOpen}>
                      <button
                        type="button"
                        aria-haspopup="menu"
                        aria-expanded={viewMenuOpen}
                        aria-label={i18n("featureViewMenuHint", { view: viewModeLabel })}
                        className="flex h-9 items-center gap-1.5 rounded-full px-3 text-sm"
                        style={{ color: "var(--text-soft)", border: "1px solid var(--border)" }}
                        onClick={() => setViewMenuOpen((open) => !open)}
                      >
                        <span aria-hidden>{LIBRARY_VIEW_ICONS[viewMode]}</span>
                        <span aria-hidden className="text-[10px]" style={{ color: "var(--dim)" }}>▾</span>
                      </button>
                    </HoverHint>
                    {viewMenuOpen ? (
                      <div
                        role="menu"
                        aria-label={i18n("featureViewLabel")}
                        className="absolute end-0 top-full z-30 mt-2 w-44 overflow-hidden rounded-xl py-1 shadow-xl"
                        style={{ background: "var(--panel-raised)", border: "1px solid var(--border-strong)" }}
                      >
                        {LIBRARY_VIEW_MODES.map((mode) => (
                          <button
                            key={mode}
                            type="button"
                            role="menuitemradio"
                            aria-checked={viewMode === mode}
                            className="flex w-full items-center gap-3 px-3 py-2 text-start text-sm hover:bg-[var(--panel-muted)]"
                            style={{ color: viewMode === mode ? "var(--text)" : "var(--text-soft)", fontWeight: viewMode === mode ? 600 : 400 }}
                            onClick={() => {
                              setViewMode(mode);
                              setViewMenuOpen(false);
                            }}
                          >
                            <span aria-hidden className="w-4 text-center">{LIBRARY_VIEW_ICONS[mode]}</span>
                            <span className="flex-1">{viewModeLabelFor(mode)}</span>
                            {viewMode === mode ? <span aria-hidden style={{ color: "var(--primary)" }}>✓</span> : null}
                          </button>
                        ))}
                      </div>
                    ) : null}
                  </div>

                  <HoverHint hint={i18n("featureNewFolderHint")} align="end">
                    <button
                      type="button"
                      aria-label={i18n("featureNewFolder")}
                      className="grid h-9 w-9 place-items-center rounded-full text-sm opacity-55 transition-opacity hover:opacity-100"
                      style={{ color: "var(--text-soft)" }}
                      onClick={() => {
                        setFolderParentId(currentFolder?.id ?? "");
                        setFolderModalOpen(true);
                      }}
                    >
                      📁+
                    </button>
                  </HoverHint>
                </div>
              </div>

              <nav aria-label={i18n("featureFilterByFolder")} className="mt-4 flex min-w-0 flex-wrap items-center gap-x-1.5 gap-y-1 text-xs" style={{ color: "var(--dim)" }}>
                <span>{i18n("featurePathLabel")}</span>
                <button
                  type="button"
                  aria-current={selectedFolderId === "all"}
                  className="hover:underline"
                  style={{ color: selectedFolderId === "all" ? "var(--text-soft)" : "var(--muted)", fontWeight: selectedFolderId === "all" ? 600 : 400 }}
                  onClick={() => setSelectedFolderId("all")}
                  {...folderDropProps(null)}
                >
                  {i18n("featureLibraryRoot")}
                </button>
                {folderPath.map((folder) => (
                  <span key={folder.id} className="inline-flex min-w-0 items-center gap-1.5">
                    <span aria-hidden>/</span>
                    <button
                      type="button"
                      aria-current={folder.id === selectedFolderId}
                      className="max-w-[12rem] truncate hover:underline"
                      style={{ color: folder.id === selectedFolderId ? "var(--text-soft)" : "var(--muted)", fontWeight: folder.id === selectedFolderId ? 600 : 400 }}
                      onClick={() => setSelectedFolderId(folder.id)}
                      {...folderDropProps(folder.id)}
                    >
                      {folder.name}
                    </button>
                  </span>
                ))}
              </nav>

              {viewMode === "folders" ? (
                <>
                  {visibleFolders.length > 0 ? (
                    <div className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                      {visibleFolders.map((folder) => {
                        const childCount = childFolders(folder.id).length;
                        const workoutCount = folderWorkouts(folder.id).length;
                        return (
                          <article
                            key={folder.id}
                            className="relative rounded-[1.2rem] p-4 transition-transform hover:-translate-y-0.5"
                            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
                            {...folderDropProps(folder.id)}
                          >
                            <button type="button" className="w-full text-start" onClick={() => setSelectedFolderId(folder.id)}>
                              <div className="flex items-center gap-3">
                                <span className="text-3xl" aria-hidden>📁</span>
                                <div className="min-w-0">
                                  <p className="truncate font-semibold" style={{ color: "var(--text)" }}>{folder.name}</p>
                                  <p className="text-xs" style={{ color: "var(--muted)" }}>{workoutCount} {i18n("workoutsccb58b2")} · {childCount} {i18n("featureViewFolders")}</p>
                                </div>
                              </div>
                            </button>
                            <div className="absolute end-3 top-3 flex gap-1">
                              <HoverHint hint={i18n("featureRenameFolder", { name: folder.name })}>
                                <button aria-label={i18n("featureRenameFolder", { name: folder.name })} type="button" className="grid h-7 w-7 place-items-center rounded-md text-xs opacity-55 hover:opacity-100" style={{ background: "var(--panel)", color: "var(--text-soft)" }} onClick={() => void renameFolder(folder)}>✎</button>
                              </HoverHint>
                              <HoverHint hint={i18n("featureDeleteFolder", { name: folder.name })} align="end">
                                <button aria-label={i18n("featureDeleteFolder", { name: folder.name })} type="button" className="grid h-7 w-7 place-items-center rounded-md text-sm opacity-55 hover:opacity-100" style={{ background: "var(--panel)", color: "var(--danger)" }} onClick={() => void removeFolder(folder)}>×</button>
                              </HoverHint>
                            </div>
                          </article>
                        );
                      })}
                    </div>
                  ) : null}
                  {visibleWorkouts.length > 0 ? (
                    <div className="mt-6 grid gap-4 lg:grid-cols-2">{visibleWorkouts.map(renderWorkoutTile)}</div>
                  ) : null}
                </>
              ) : (
                <div className="mt-6 space-y-3">
                  {renderWorkoutCollection(visibleWorkouts)}
                  {visibleFolders.map((folder) => renderFolderGroup(folder, 0))}
                </div>
              )}

              {visibleFolders.length === 0 && visibleWorkouts.length === 0 ? (
                <p className="mt-6 text-sm" style={{ color: "var(--dim)" }}>{i18n("featureEmptyFolder")}</p>
              ) : null}
            </section>
          </>
        )}
      </div>

      {folderModalOpen ? (
        <div className="fixed inset-0 z-[70] flex items-center justify-center p-4" style={{ background: "rgba(0,0,0,.65)" }} onClick={() => setFolderModalOpen(false)} role="presentation">
          <form
            className="w-full max-w-md rounded-[1.5rem] p-5 shadow-[0_30px_90px_rgba(0,0,0,.35)]"
            style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
            onClick={(event) => event.stopPropagation()}
            onSubmit={(event) => {
              event.preventDefault();
              void addFolder();
            }}
          >
            <div className="flex items-start justify-between gap-4">
              <div>
                <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--primary)" }}>{i18n("featureNewFolder")}</p>
                <h2 className="mt-1 text-xl font-semibold" style={{ color: "var(--text)" }}>{i18n("featureAddFolder")}</h2>
              </div>
              <button type="button" className="rounded-full px-3 py-1.5 text-xs font-semibold" style={{ background: "var(--border)", color: "var(--muted)" }} onClick={() => setFolderModalOpen(false)}>
                {i18n("closebbfa773")}
              </button>
            </div>
            <label className="mt-5 block text-sm font-semibold" style={{ color: "var(--muted)" }}>
              {i18n("featureFolderName")}
              <input aria-label={i18n("featureNewFolderName")} className="mt-2 w-full rounded-xl px-3 py-2 text-sm" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }} value={folderName} onChange={(event) => setFolderName(event.target.value)} />
            </label>
            <label className="mt-4 block text-sm font-semibold" style={{ color: "var(--muted)" }}>
              {i18n("featureParentFolder")}
              <select aria-label={i18n("featureParentFolder")} className="mt-2 w-full rounded-xl px-3 py-2 text-sm" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }} value={folderParentId} onChange={(event) => setFolderParentId(event.target.value)}>
                <option value="">{i18n("featureLibraryRoot")}</option>
                {orderedFolders.map((folder) => <option key={folder.id} value={folder.id}>{folderLabel(folder)}</option>)}
              </select>
            </label>
            <div className="mt-5 flex justify-end gap-2">
              <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ background: "var(--border)", color: "var(--text-soft)" }} onClick={() => setFolderModalOpen(false)}>
                {i18n("cancel77dfd21")}
              </button>
              <button type="submit" disabled={!folderName.trim() || busyAction === "create-folder"} className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
                {i18n("featureAddFolder")}
              </button>
            </div>
          </form>
        </div>
      ) : null}

      {editTarget && tokens?.access_token ? (
        <WorkoutEditModal
          key={editTarget.id}
          workoutId={editTarget.id}
          workoutTitle={editTarget.title ?? i18n("untitledWorkouta1885a5")}
          accessToken={tokens.access_token}
          context={{ kind: "global" }}
          onClose={() => setEditTarget(null)}
        />
      ) : null}

      {assignTarget ? (
        <AssignWorkoutPanel
          workoutId={assignTarget.id}
          onClose={() => setAssignTarget(null)}
          onAssigned={() => {
            setAssignTarget(null);
            void listAdminWorkouts(tokens!.access_token!).then(setWorkouts).catch(() => undefined);
          }}
        />
      ) : null}

      {previewWorkoutId ? (() => {
        const pw = workouts.find((w) => w.id === previewWorkoutId);
        if (!pw) return null;
        return (
          <>
            <div
              className="fixed inset-0 z-40"
              style={{ background: "rgba(0,0,0,0.45)" }}
              onClick={() => setPreviewWorkoutId(null)}
            />
            <aside
              className="fixed end-0 top-0 z-50 flex h-full flex-col overflow-hidden"
              style={{
                width: "min(480px, 90vw)",
                background: "var(--panel)",
                borderInlineStart: "1px solid var(--border)",
                boxShadow: "-8px 0 32px rgba(0,0,0,0.18)",
              }}
            >
              <div className="flex shrink-0 items-start justify-between gap-4 border-b px-6 py-5" style={{ borderColor: "var(--border)" }}>
                <div>
                  <p className="text-xs font-semibold uppercase tracking-[0.22em]" style={{ color: "var(--primary)" }}><SemanticLabel value={pw.type} /></p>
                  <h2 className="mt-1 text-xl font-semibold" style={{ color: "var(--text)" }}>{pw.title || i18n("untitledWorkouta1885a5")}</h2>
                  <p className="mt-1 text-sm" style={{ color: "var(--dim)" }}>
                    {pw.available_scale_levels.length > 0 ? i18n("scaleLevelCount", {count: pw.available_scale_levels.length}) : i18n("baseOnly061c4ff")}
                  </p>
                </div>
                <button
                  className="shrink-0 rounded-full px-4 py-2 text-sm font-semibold"
                  style={{ background: "var(--border)", color: "var(--text-soft)" }}
                  onClick={() => setPreviewWorkoutId(null)}
                  type="button"
                >
                  {i18n("closebbfa773")}
                </button>
              </div>
              <div className="flex-1 overflow-y-auto px-6 py-5">
                <WorkoutPreviewDetail
                  sections={pw.sections}
                  initiallyExpanded
                  authoringMode={pw.authoring_mode}
                  freeTextBody={pw.free_text_body}
                  freeTextDocument={pw.free_text_document}
                />
              </div>
            </aside>
          </>
        );
      })() : null}

      {shareTarget ? (
        <ShareExportDialog
          copy={shareExport.copy}
          document={buildWorkoutDocument(shareTarget, shareExport.labels)}
          onClose={() => setShareTarget(null)}
        />
      ) : null}
    </main>
  );
}
