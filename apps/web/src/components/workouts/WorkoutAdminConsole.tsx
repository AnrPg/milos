"use client";

import { useUiTranslations } from "@/i18n/ui";
import { localizeError } from "@/i18n/presentation";
import { useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useLocale } from "next-intl";

import { ApiError } from "@/api/client";
import {
  copyWorkoutToFolder,
  createWorkoutFolder,
  deleteWorkoutFolder,
  deleteWorkout,
  listWorkoutFolders,
  listAdminWorkouts,
  moveWorkoutToFolder,
  setWorkoutIcon,
  updateWorkoutFolder,
  type WorkoutFolder,
  type WorkoutRecord,
} from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { HoverHint } from "@/components/HelpTooltip";
import { USER_SYNC_EVENT, type UserSyncDetail } from "@/lib/user-sync";
import { AssignWorkoutPanel } from "@/components/workouts/AssignWorkoutPanel";
import { WorkoutEditModal } from "@/components/workouts/WorkoutEditModal";
import { WorkoutPreviewDetail } from "@/components/workouts/WorkoutPreviewDetail";
import { LibraryIconDialog } from "@/components/workouts/library/LibraryIconDialog";
import { LibraryItemMenu, type LibraryMenuAction } from "@/components/workouts/library/LibraryItemMenu";
import { LibraryTransferDialog, type FolderOption } from "@/components/workouts/library/LibraryTransferDialog";
import {
  compareFolders,
  dayFolderBadge,
  folderDisplayName,
  folderIcon,
  folderKind,
  folderSubtreeIds,
  resolveWorkoutIcon,
  ruleIcon,
  workoutIcon,
} from "@/components/workouts/library/library-folders";
import { SemanticLabel } from "@/components/semantic-label";
import { ShareExportDialog } from "@/components/share-export/ShareExportDialog";
import { useShareExport } from "@/components/share-export/useShareExport";
import { buildWorkoutDocument } from "@/lib/document-export";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { PageHeader } from "@/components/PageHeader";
import { Dialog } from "@/components/ui/Dialog";

type LibraryViewMode = "folders" | "tiles" | "list";

const LIBRARY_VIEW_MODES: readonly LibraryViewMode[] = ["folders", "tiles", "list"];
const LIBRARY_VIEW_ICONS: Record<LibraryViewMode, string> = { folders: "📁", tiles: "▦", list: "☰" };

type Transfer =
  | { kind: "move-workout" | "copy-workout"; workout: WorkoutRecord }
  | { kind: "move-folder"; folder: WorkoutFolder };

export function WorkoutAdminConsole() {
  const i18n = useUiTranslations();
  const locale = useLocale();
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
  // Tiles view starts expanded (sets hold collapsed ids); the list tree starts collapsed like an OS tree.
  const [collapsedFolderIds, setCollapsedFolderIds] = useState<Set<string>>(() => new Set());
  const [expandedTreeIds, setExpandedTreeIds] = useState<Set<string>>(() => new Set());
  const [openMenuKey, setOpenMenuKey] = useState<string | null>(null);
  const [transfer, setTransfer] = useState<Transfer | null>(null);
  const [iconTarget, setIconTarget] = useState<WorkoutRecord | null>(null);
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

  const setMenuOpen = useCallback((key: string, open: boolean) => {
    setOpenMenuKey((current) => (open ? key : current === key ? null : current));
  }, []);

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

  const folderLabels = {
    athletes: i18n("featureAthletesFolder"),
    classes: i18n("featureClassesFolder"),
    memberVariations: i18n("featureMemberVariationsFolder"),
  };
  const displayName = (folder: WorkoutFolder) => folderDisplayName(folder, folderLabels, locale);
  const folderById = new Map(folders.map((folder) => [folder.id, folder]));
  const currentFolder = typeof selectedFolderId === "string" && selectedFolderId !== "all" ? folderById.get(selectedFolderId) : undefined;
  const pathOf = (folder: WorkoutFolder) => {
    const parts: WorkoutFolder[] = [];
    let node: WorkoutFolder | undefined = folder;
    while (node) {
      parts.unshift(node);
      node = node.parent_id ? folderById.get(node.parent_id) : undefined;
    }
    return parts;
  };
  const folderLabel = (folder: WorkoutFolder) => pathOf(folder).map(displayName).join(" / ");
  const folderPath = currentFolder ? pathOf(currentFolder) : [];
  const orderedFolders = [...folders].sort((a, b) => {
    const pathA = pathOf(a);
    const pathB = pathOf(b);
    for (let index = 0; index < Math.min(pathA.length, pathB.length); index += 1) {
      if (pathA[index].id !== pathB[index].id) return compareFolders(pathA[index], pathB[index]);
    }
    return pathA.length - pathB.length;
  });
  const viewModeLabelFor = (mode: LibraryViewMode) => i18n(`featureView${mode[0].toUpperCase()}${mode.slice(1)}`);
  const viewModeLabel = viewModeLabelFor(viewMode);
  // Every view is rooted at the folder picked in the path; folder view shows one level,
  // tiles and list views show the whole subtree grouped by folder.
  const treeRootId = selectedFolderId === "all" ? null : selectedFolderId;
  const childFolders = (parentId: string | null) =>
    folders.filter((folder) => (folder.parent_id ?? null) === parentId).sort(compareFolders);
  const folderWorkouts = (folderId: string | null) =>
    workouts
      .filter((workout) => (workout.folder_id ?? null) === folderId)
      .sort((a, b) => String(a[sortKey] ?? "").localeCompare(String(b[sortKey] ?? "")));
  const subtreeWorkoutCount = (folderId: string): number =>
    folderWorkouts(folderId).length + childFolders(folderId).reduce((total, child) => total + subtreeWorkoutCount(child.id), 0);
  const visibleFolders = childFolders(treeRootId);
  const visibleWorkouts = folderWorkouts(treeRootId);
  const toggleIn = (setter: typeof setCollapsedFolderIds) => (folderId: string) => {
    setter((current) => {
      const next = new Set(current);
      if (next.has(folderId)) next.delete(folderId);
      else next.add(folderId);
      return next;
    });
  };
  const toggleFolderGroup = toggleIn(setCollapsedFolderIds);
  const toggleTreeFolder = toggleIn(setExpandedTreeIds);
  const newWorkoutHref = adminHref(currentFolder ? `/admin/workouts/new?folder=${currentFolder.id}` : "/admin/workouts/new", organizationSlug);
  const newWorkoutHint = currentFolder
    ? i18n("featureNewWorkoutInFolderHint", { folder: displayName(currentFolder) })
    : i18n("featureNewWorkoutHint");

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

  async function moveWorkout(workoutId: string, folderId: string | null) {
    if (!tokens?.access_token) return;
    await runAction(`move-${workoutId}`, async () => {
      await moveWorkoutToFolder(tokens.access_token!, workoutId, folderId);
      setWorkouts((current) => current.map((item) => item.id === workoutId ? { ...item, folder_id: folderId } : item));
    });
  }

  async function moveDraggedWorkout(folderId: string | null) {
    if (!draggedWorkoutId) return;
    const workoutId = draggedWorkoutId;
    setDraggedWorkoutId(null);
    await moveWorkout(workoutId, folderId);
  }

  async function copyWorkout(workout: WorkoutRecord, folderId: string | null) {
    if (!tokens?.access_token) return;
    await runAction(`copy-${workout.id}`, async () => {
      await copyWorkoutToFolder(tokens.access_token!, workout.id, folderId);
      setWorkouts(await listAdminWorkouts(tokens.access_token!));
      setMessage(i18n("featureCopiedWorkout", { name: workout.title || i18n("untitledWorkouta1885a5") }));
    });
  }

  async function saveIcon(workout: WorkoutRecord, icon: string | null) {
    if (!tokens?.access_token) return;
    await runAction(`icon-${workout.id}`, async () => {
      const updated = await setWorkoutIcon(tokens.access_token!, workout.id, icon);
      setWorkouts((current) => current.map((item) => item.id === updated.id ? { ...item, icon: updated.icon, icon_source: updated.icon_source } : item));
      setIconTarget(null);
    });
  }

  async function saveFolder(folder: WorkoutFolder, changes: { name?: string; parent_id?: string | null }) {
    if (!tokens?.access_token) return;
    await runAction(`folder-${folder.id}`, async () => {
      const updated = await updateWorkoutFolder(tokens.access_token!, folder.id, {
        name: changes.name ?? folder.name,
        parent_id: changes.parent_id === undefined ? folder.parent_id : changes.parent_id,
      });
      setFolders((current) => current.map((item) => item.id === updated.id ? { ...item, ...updated } : item));
    });
  }

  async function renameFolder(folder: WorkoutFolder) {
    const name = window.prompt(i18n("featureFolderName"), displayName(folder))?.trim();
    if (!name || name === displayName(folder)) return;
    await saveFolder(folder, { name });
  }

  async function removeFolder(folder: WorkoutFolder) {
    if (!tokens?.access_token || !window.confirm(
      i18n("featureDeleteFolderConfirm", { name: displayName(folder) }),
    )) return;
    await runAction(`folder-${folder.id}`, async () => {
      await deleteWorkoutFolder(tokens.access_token!, folder.id);
      setFolders((current) => current.filter((item) => item.id !== folder.id).map((item) => item.parent_id === folder.id ? { ...item, parent_id: folder.parent_id } : item));
      setWorkouts((current) => current.map((item) => item.folder_id === folder.id ? { ...item, folder_id: folder.parent_id } : item));
      if (selectedFolderId === folder.id) setSelectedFolderId(folder.parent_id ?? "all");
    });
  }

  function folderOptions(excluded: Set<string> = new Set()): FolderOption[] {
    return [
      { id: null, label: i18n("featureLibraryRoot") },
      ...orderedFolders.map((folder) => ({ id: folder.id, label: folderLabel(folder), disabled: excluded.has(folder.id) })),
    ];
  }

  function workoutActions(workout: WorkoutRecord): LibraryMenuAction[] {
    const actions: LibraryMenuAction[] = [{ key: "open", icon: "👁", label: i18n("featureOpen"), onSelect: () => setPreviewWorkoutId(workout.id) }];
    if (workout.status === "published") {
      actions.push(
        { key: "assign", icon: "🎯", label: i18n("featureAssignToAthleteOrClass"), onSelect: () => setAssignTarget(workout) },
        { key: "edit", icon: "✎", label: i18n("edit5301648"), onSelect: () => setEditTarget(workout) },
      );
    } else {
      actions.push({
        key: "continue",
        icon: "✎",
        label: i18n("continueEditingb101465"),
        onSelect: () => router.push(adminHref(`/admin/workouts/new?draft=${workout.id}`, organizationSlug)),
      });
    }
    actions.push(
      { key: "icon", icon: resolveWorkoutIcon(workout), label: i18n("featureChangeIcon"), onSelect: () => setIconTarget(workout) },
      { key: "move", icon: "↪", label: i18n("featureMoveToFolder"), onSelect: () => setTransfer({ kind: "move-workout", workout }) },
      { key: "copy", icon: "⧉", label: i18n("featureCopyToFolder"), onSelect: () => setTransfer({ kind: "copy-workout", workout }) },
      { key: "share", icon: "⇪", label: shareExport.copy.title, onSelect: () => setShareTarget(workout) },
      { key: "delete", icon: "🗑", label: i18n("deletef6fdbe4"), danger: true, disabled: busyAction === `delete-${workout.id}`, onSelect: () => void handleDeleteWorkout(workout) },
    );
    return actions;
  }

  function folderActions(folder: WorkoutFolder): LibraryMenuAction[] {
    return [
      { key: "open", icon: "📂", label: i18n("featureOpen"), onSelect: () => setSelectedFolderId(folder.id) },
      { key: "new", icon: "＋", label: i18n("featureNewWorkoutButton"), onSelect: () => router.push(adminHref(`/admin/workouts/new?folder=${folder.id}`, organizationSlug)) },
      { key: "rename", icon: "✎", label: i18n("featureRenameFolder", { name: displayName(folder) }), onSelect: () => void renameFolder(folder) },
      { key: "move", icon: "↪", label: i18n("featureMoveToFolder"), onSelect: () => setTransfer({ kind: "move-folder", folder }) },
      { key: "delete", icon: "🗑", label: i18n("featureDeleteFolder", { name: displayName(folder) }), danger: true, onSelect: () => void removeFolder(folder) },
    ];
  }

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

  function workoutDragProps(workout: WorkoutRecord) {
    return {
      draggable: true,
      onDragStart: () => setDraggedWorkoutId(workout.id),
      onDragEnd: () => setDraggedWorkoutId(null),
    };
  }

  function folderHint(folder: WorkoutFolder) {
    const kind = folderKind(folder);
    if (kind === "athletes") return i18n("featureAthletesFolderHint");
    if (kind === "classes") return i18n("featureClassesFolderHint");
    if (kind === "memberVariations") return i18n("featureMemberVariationsFolderHint");
    return null;
  }

  // ── Folder view: an OS-style file explorer ─────────────────────────────────

  function renderExplorerFolder(folder: WorkoutFolder) {
    const menuKey = `folder:${folder.id}`;
    const count = subtreeWorkoutCount(folder.id);
    const hint = folderHint(folder);
    const badge = dayFolderBadge(folder, locale);
    const tile = (
      <button
        type="button"
        className="flex w-full flex-col items-center gap-1.5 rounded-xl px-2 pb-2.5 pt-3 text-center transition-colors hover:bg-[var(--panel-muted)] focus-visible:bg-[var(--panel-muted)]"
        onClick={() => setSelectedFolderId(folder.id)}
        onContextMenu={(event) => {
          event.preventDefault();
          setMenuOpen(menuKey, true);
        }}
      >
        <span aria-hidden className="relative text-[2.6rem] leading-none drop-shadow-sm">
          {badge ? (
            <span className="flex h-[2.6rem] w-[2.4rem] flex-col overflow-hidden rounded-md text-center shadow-sm" style={{ background: "var(--text)", border: "1px solid var(--border)" }}>
              <span className="text-[9px] font-bold uppercase leading-[0.9rem]" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>{badge.month}</span>
              <span className="flex-1 text-lg font-bold leading-[1.6rem]" style={{ color: "var(--bg)" }}>{badge.day}</span>
            </span>
          ) : folderIcon(folder)}
          {count > 0 ? (
            <span className="absolute -bottom-1 -end-2 min-w-5 rounded-full px-1 text-[10px] font-bold leading-4" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
              {count}
            </span>
          ) : null}
        </span>
        <span className="line-clamp-2 w-full break-words text-xs font-medium leading-4" style={{ color: "var(--text)" }}>{displayName(folder)}</span>
      </button>
    );

    return (
      <div key={folder.id} role="listitem" className="group relative" {...folderDropProps(folder.id)}>
        {hint ? <HoverHint hint={hint}>{tile}</HoverHint> : tile}
        <LibraryItemMenu
          label={i18n("featureItemActions", { name: displayName(folder) })}
          actions={folderActions(folder)}
          open={openMenuKey === menuKey}
          onOpenChange={(open) => setMenuOpen(menuKey, open)}
          className="absolute end-0.5 top-0.5 opacity-0 transition-opacity focus-within:opacity-100 group-hover:opacity-100 max-sm:opacity-100"
        />
      </div>
    );
  }

  function renderExplorerWorkout(workout: WorkoutRecord) {
    const menuKey = `workout:${workout.id}`;
    const title = workout.title || i18n("untitledWorkouta1885a5");
    return (
      <div key={workout.id} role="listitem" className="group relative">
        <button
          type="button"
          {...workoutDragProps(workout)}
          className="flex w-full flex-col items-center gap-1.5 rounded-xl px-2 pb-2.5 pt-3 text-center transition-colors hover:bg-[var(--panel-muted)] focus-visible:bg-[var(--panel-muted)]"
          onClick={() => setPreviewWorkoutId(workout.id)}
          onContextMenu={(event) => {
            event.preventDefault();
            setMenuOpen(menuKey, true);
          }}
        >
          <span aria-hidden className="relative grid h-[2.6rem] w-[2.2rem] place-items-center rounded-md text-2xl leading-none shadow-sm" style={{ background: "color-mix(in srgb, var(--primary) 14%, var(--panel-muted))", border: "1px solid color-mix(in srgb, var(--primary) 30%, var(--border))" }}>
            {resolveWorkoutIcon(workout)}
            {workout.status === "draft" ? (
              <span className="absolute -end-1 -top-1 h-2.5 w-2.5 rounded-full" style={{ background: "var(--warning)", boxShadow: "0 0 0 2px var(--panel)" }} />
            ) : null}
          </span>
          <span className="line-clamp-2 w-full break-words text-xs font-medium leading-4" style={{ color: "var(--text)" }}>{title}</span>
          <span className="w-full truncate text-[10px] leading-3" style={{ color: workout.status === "draft" ? "var(--warning)" : "var(--dim)" }}>
            {workout.status === "draft" ? i18n("draft23d33e2") : <SemanticLabel value={workout.type} />}
          </span>
        </button>
        <LibraryItemMenu
          label={i18n("featureItemActions", { name: title })}
          actions={workoutActions(workout)}
          open={openMenuKey === menuKey}
          onOpenChange={(open) => setMenuOpen(menuKey, open)}
          className="absolute end-0.5 top-0.5 opacity-0 transition-opacity focus-within:opacity-100 group-hover:opacity-100 max-sm:opacity-100"
        />
      </div>
    );
  }

  // ── List view: a plain-text folder tree ────────────────────────────────────

  function renderTreeLevel(parentId: string | null, depth: number): React.ReactNode {
    return (
      <>
        {childFolders(parentId).map((folder) => renderTreeFolder(folder, depth))}
        {folderWorkouts(parentId).map((workout) => renderTreeWorkout(workout, depth))}
      </>
    );
  }

  function renderTreeFolder(folder: WorkoutFolder, depth: number) {
    const expanded = expandedTreeIds.has(folder.id);
    const menuKey = `folder:${folder.id}`;
    return (
      <div key={folder.id} role="treeitem" aria-expanded={expanded} aria-selected={false}>
        <div className="group flex items-center gap-1" style={{ paddingInlineStart: `${depth * 1.25}rem` }} {...folderDropProps(folder.id)}>
          <button
            type="button"
            className="flex min-w-0 items-center gap-2 py-1.5 text-start text-sm hover:text-[var(--text)]"
            style={{ color: "var(--text-soft)" }}
            onClick={() => toggleTreeFolder(folder.id)}
            onContextMenu={(event) => {
              event.preventDefault();
              setMenuOpen(menuKey, true);
            }}
          >
            <span aria-hidden className="inline-block w-3 text-[10px] transition-transform" style={{ color: "var(--dim)", transform: expanded ? "rotate(90deg)" : undefined }}>▶</span>
            <span aria-hidden>{folderIcon(folder)}</span>
            <span className="truncate font-medium">{displayName(folder)}</span>
            <span className="text-xs tabular-nums" style={{ color: "var(--dim)" }}>{subtreeWorkoutCount(folder.id)}</span>
          </button>
          <LibraryItemMenu
            label={i18n("featureItemActions", { name: displayName(folder) })}
            actions={folderActions(folder)}
            open={openMenuKey === menuKey}
            onOpenChange={(open) => setMenuOpen(menuKey, open)}
            className="opacity-0 transition-opacity focus-within:opacity-100 group-hover:opacity-100 max-sm:opacity-100"
          />
        </div>
        {expanded ? <div role="group">{renderTreeLevel(folder.id, depth + 1)}</div> : null}
      </div>
    );
  }

  function renderTreeWorkout(workout: WorkoutRecord, depth: number) {
    const menuKey = `workout:${workout.id}`;
    const title = workout.title || i18n("untitledWorkouta1885a5");
    return (
      <div key={workout.id} role="treeitem" aria-selected={false} className="group flex items-center gap-1" style={{ paddingInlineStart: `${depth * 1.25 + 1}rem` }}>
        <button
          type="button"
          {...workoutDragProps(workout)}
          className="flex min-w-0 items-center gap-2 py-1.5 text-start text-sm hover:text-[var(--text)]"
          style={{ color: "var(--text-soft)" }}
          onClick={() => setPreviewWorkoutId(workout.id)}
          onContextMenu={(event) => {
            event.preventDefault();
            setMenuOpen(menuKey, true);
          }}
        >
          <span aria-hidden>{resolveWorkoutIcon(workout)}</span>
          <span className="truncate">{title}</span>
          <span className="shrink-0 text-xs" style={{ color: "var(--dim)" }}><SemanticLabel value={workout.type} /></span>
          {workout.status === "draft" ? <span className="shrink-0 text-xs" style={{ color: "var(--warning)" }}>· {i18n("draft23d33e2")}</span> : null}
        </button>
        <LibraryItemMenu
          label={i18n("featureItemActions", { name: title })}
          actions={workoutActions(workout)}
          open={openMenuKey === menuKey}
          onOpenChange={(open) => setMenuOpen(menuKey, open)}
          className="opacity-0 transition-opacity focus-within:opacity-100 group-hover:opacity-100 max-sm:opacity-100"
        />
      </div>
    );
  }

  // ── Tiles view: workout cards grouped in collapsible folder sections ───────

  function renderWorkoutTile(workout: WorkoutRecord) {
    const menuKey = `tile:${workout.id}`;
    return (
      <article
        key={workout.id}
        className="rounded-[1.5rem] p-5"
        {...workoutDragProps(workout)}
        style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", cursor: "pointer" }}
        onClick={() => setPreviewWorkoutId(workout.id)}
      >
        <div className="flex items-start justify-between gap-4">
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
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
          <LibraryItemMenu
            label={i18n("featureItemActions", { name: workout.title || i18n("untitledWorkouta1885a5") })}
            actions={workoutActions(workout)}
            open={openMenuKey === menuKey}
            onOpenChange={(open) => setMenuOpen(menuKey, open)}
            className="shrink-0"
          />
        </div>

        <div className="mt-4 flex flex-wrap gap-2" onClick={(e) => e.stopPropagation()}>
          {workout.status === "draft" ? (
            <Link
              className="rounded-full px-3 py-1 text-xs font-semibold"
              style={{ background: "var(--text)", color: "var(--bg)" }}
              href={adminHref(`/admin/workouts/new?draft=${workout.id}`, organizationSlug)}
            >
              {i18n("continueEditingb101465")}
            </Link>
          ) : (
            <button
              className="rounded-full px-3 py-1 text-xs font-semibold"
              style={{ background: "var(--text)", color: "var(--bg)" }}
              onClick={() => setAssignTarget(workout)}
              type="button"
            >
              {i18n("featureAssignToAthleteOrClass")}
            </button>
          )}

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

  function renderTileGroup(folder: WorkoutFolder, depth: number): React.ReactNode {
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
          <span aria-hidden>{folderIcon(folder)}</span>
          <span className="min-w-0 flex-1 truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{displayName(folder)}</span>
          <span className="text-xs tabular-nums" style={{ color: "var(--muted)" }}>{subtreeWorkoutCount(folder.id)}</span>
        </button>
        {!collapsed ? (
          <div className="space-y-3 px-3 pb-3 sm:px-4 sm:pb-4">
            {items.length > 0 ? <div className="grid gap-4 lg:grid-cols-2">{items.map(renderWorkoutTile)}</div> : null}
            {subfolders.map((child) => renderTileGroup(child, depth + 1))}
            {items.length === 0 && subfolders.length === 0 ? (
              <p className="px-1 text-xs" style={{ color: "var(--dim)" }}>{i18n("featureEmptyFolder")}</p>
            ) : null}
          </div>
        ) : null}
      </section>
    );
  }

  function renderTransferDialog() {
    if (!transfer) return null;
    if (transfer.kind === "move-folder") {
      const { folder } = transfer;
      return (
        <LibraryTransferDialog
          key={`move-folder-${folder.id}`}
          title={i18n("featureMoveItemTitle", { name: displayName(folder) })}
          confirmLabel={i18n("featureMoveHere")}
          options={folderOptions(folderSubtreeIds(folders, folder.id))}
          initialFolderId={folder.parent_id}
          busy={busyAction === `folder-${folder.id}`}
          onCancel={() => setTransfer(null)}
          onConfirm={(parentId) => {
            setTransfer(null);
            void saveFolder(folder, { parent_id: parentId });
          }}
        />
      );
    }
    const { workout, kind } = transfer;
    const name = workout.title || i18n("untitledWorkouta1885a5");
    const copying = kind === "copy-workout";
    return (
      <LibraryTransferDialog
        key={`${kind}-${workout.id}`}
        title={i18n(copying ? "featureCopyItemTitle" : "featureMoveItemTitle", { name })}
        confirmLabel={i18n(copying ? "featureCopyHere" : "featureMoveHere")}
        options={folderOptions()}
        initialFolderId={workout.folder_id ?? null}
        busy={busyAction === `${copying ? "copy" : "move"}-${workout.id}`}
        onCancel={() => setTransfer(null)}
        onConfirm={(folderId) => {
          setTransfer(null);
          void (copying ? copyWorkout(workout, folderId) : moveWorkout(workout.id, folderId));
        }}
      />
    );
  }

  const libraryEmpty = visibleFolders.length === 0 && visibleWorkouts.length === 0;

  return (
    <main className="min-h-screen px-6 py-8 md:px-10 md:py-12" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-7xl space-y-8">
        <PageHeader title={i18n("workoutsccb58b2")} />

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
                <HoverHint hint={newWorkoutHint} align="start">
                  <Link
                    className="inline-flex h-12 items-center gap-2 rounded-2xl px-5 text-base font-bold transition-transform hover:-translate-y-0.5"
                    style={{ background: "var(--primary)", color: "var(--primary-contrast)", boxShadow: "0 12px 30px color-mix(in srgb, var(--primary) 35%, transparent)" }}
                    href={newWorkoutHref}
                  >
                    <span aria-hidden className="text-xl leading-none">+</span>
                    <span className="inline-flex items-center gap-1.5">
                      <span aria-hidden className="hidden text-xl leading-none sm:inline">🏋️</span>
                      {i18n("featureNewWorkoutButton")}
                    </span>
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
                      className="relative grid h-9 w-9 place-items-center rounded-full text-base opacity-60 transition-opacity hover:opacity-100"
                      style={{ color: "var(--text-soft)" }}
                      onClick={() => {
                        setFolderParentId(currentFolder?.id ?? "");
                        setFolderModalOpen(true);
                      }}
                    >
                      <span aria-hidden>📂</span>
                      <span aria-hidden className="absolute bottom-1 end-0.5 grid h-3.5 w-3.5 place-items-center rounded-full text-[10px] font-black leading-none" style={{ background: "var(--success)", color: "var(--success-contrast)" }}>+</span>
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
                      {displayName(folder)}
                    </button>
                  </span>
                ))}
              </nav>

              {viewMode === "folders" && !libraryEmpty ? (
                <div role="list" className="mt-5 grid grid-cols-[repeat(auto-fill,minmax(6.25rem,1fr))] gap-1 sm:gap-2">
                  {visibleFolders.map(renderExplorerFolder)}
                  {visibleWorkouts.map(renderExplorerWorkout)}
                </div>
              ) : null}

              {viewMode === "list" && !libraryEmpty ? (
                <div role="tree" aria-label={i18n("semanticWorkoutLibrary")} className="mt-5">
                  {renderTreeLevel(treeRootId, 0)}
                </div>
              ) : null}

              {viewMode === "tiles" && !libraryEmpty ? (
                <div className="mt-6 space-y-3">
                  {visibleWorkouts.length > 0 ? <div className="grid gap-4 lg:grid-cols-2">{visibleWorkouts.map(renderWorkoutTile)}</div> : null}
                  {visibleFolders.map((folder) => renderTileGroup(folder, 0))}
                </div>
              ) : null}

              {libraryEmpty ? (
                <p className="mt-6 text-sm" style={{ color: "var(--dim)" }}>{i18n("featureEmptyFolder")}</p>
              ) : null}
            </section>
          </>
        )}
      </div>

      {folderModalOpen ? (
        <Dialog
          onClose={() => setFolderModalOpen(false)}
          eyebrow={i18n("featureNewFolder")}
          title={i18n("featureAddFolder")}
          closeLabel={i18n("closebbfa773")}
          size="md"
          variant="center"
          onSubmit={(event) => {
              event.preventDefault();
              void addFolder();
            }}
          footer={
            <div className="w-full flex justify-end gap-2">
              <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ background: "var(--border)", color: "var(--text-soft)" }} onClick={() => setFolderModalOpen(false)}>
                {i18n("cancel77dfd21")}
              </button>
              <button type="submit" disabled={!folderName.trim() || busyAction === "create-folder"} className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
                {i18n("featureAddFolder")}
              </button>
            </div>
          }
        >
            
            <label className="block text-sm font-semibold" style={{ color: "var(--muted)" }}>
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
        </Dialog>
      ) : null}

      {renderTransferDialog()}

      {iconTarget ? (
        <LibraryIconDialog
          key={iconTarget.id}
          workoutTitle={iconTarget.title || i18n("untitledWorkouta1885a5")}
          currentIcon={resolveWorkoutIcon(iconTarget)}
          automaticIcon={ruleIcon(iconTarget.title) ?? workoutIcon(iconTarget.type)}
          isCustom={iconTarget.icon_source === "coach"}
          busy={busyAction === `icon-${iconTarget.id}`}
          onCancel={() => setIconTarget(null)}
          onSave={(icon) => void saveIcon(iconTarget, icon)}
        />
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
            // Assigned workouts are filed as copies in athlete/class folders.
            void reloadAdminData();
          }}
        />
      ) : null}

      {previewWorkoutId ? (() => {
        const pw = workouts.find((w) => w.id === previewWorkoutId);
        if (!pw) return null;
        return (
          <Dialog
            onClose={() => setPreviewWorkoutId(null)}
            variant="drawer"
            size="lg"
            eyebrow={<SemanticLabel value={pw.type} />}
            title={pw.title || i18n("untitledWorkouta1885a5")}
            description={pw.available_scale_levels.length > 0 ? i18n("scaleLevelCount", {count: pw.available_scale_levels.length}) : i18n("baseOnly061c4ff")}
            closeLabel={i18n("closebbfa773")}
          >
                <WorkoutPreviewDetail
                  sections={pw.sections}
                  content={pw.content}
                  initiallyExpanded
                  authoringMode={pw.authoring_mode}
                  freeTextBody={pw.free_text_body}
                  freeTextDocument={pw.free_text_document}
                />
          </Dialog>
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
