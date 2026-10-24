"use client";

import { useEffect, useMemo, useState, type ReactNode } from "react";
import { useTranslations } from "next-intl";

import type { VaultGroup } from "@/api/account-training";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { useSourceName } from "@/components/providers/SourceLabel";
import { SemanticLabel } from "@/components/semantic-label";
import { useUiTranslations } from "@/i18n/ui";
import { folderTrail, VAULT_VIEW_MODES, vaultFolders, type VaultFolder, type VaultViewMode } from "@/lib/vault-folders";

const VIEW_KEY = "palee.vault.view";

function storedMode(): VaultViewMode {
  try {
    const value = window.localStorage.getItem(VIEW_KEY);
    return VAULT_VIEW_MODES.includes(value as VaultViewMode) ? (value as VaultViewMode) : "folders";
  } catch {
    return "folders";
  }
}

/**
 * Vault's two views (ANR 2026-10-24, like the staff WOD library): «Φάκελοι»,
 * folder tiles to open one level at a time with a breadcrumb back, and
 * «Λίστα», the same folders as an expandable tree. The folders come from
 * `vaultFolders` (source, then workout type); the choice is remembered on
 * this device.
 */
export function VaultBrowser({ groups, renderGroup }: { groups: VaultGroup[]; renderGroup: (group: VaultGroup) => ReactNode }) {
  const i18n = useUiTranslations();
  const t = useTranslations("Providers");
  const [mode, setMode] = useState<VaultViewMode>("folders");
  const roots = useMemo(() => vaultFolders(groups), [groups]);

  useEffect(() => {
    queueMicrotask(() => setMode(storedMode()));
  }, []);

  function choose(next: VaultViewMode) {
    setMode(next);
    try {
      window.localStorage.setItem(VIEW_KEY, next);
    } catch {
      // A private window keeps the choice for this visit only.
    }
  }

  return (
    <div className="flex flex-col gap-3">
      <SegmentPicker
        ariaLabel={t("vault.view")}
        value={mode}
        onChange={choose}
        options={[
          { value: "folders", label: i18n("featureViewFolders") },
          { value: "tree", label: i18n("featureViewList") },
        ]}
        idPrefix="vault-view"
        panelId="vault-view-panel"
      />
      <div id="vault-view-panel" role="tabpanel" aria-labelledby={`vault-view-tab-${mode}`}>
        {mode === "folders" ? <FolderView roots={roots} renderGroup={renderGroup} /> : <TreeView roots={roots} renderGroup={renderGroup} />}
      </div>
    </div>
  );
}

function FolderName({ folder }: { folder: VaultFolder }) {
  const t = useTranslations("Providers");
  const sourceName = useSourceName();
  if (folder.label.kind === "source") return <>{sourceName(folder.label.source)}</>;
  return folder.label.type ? <SemanticLabel value={folder.label.type} /> : <>{t("vault.otherType")}</>;
}

function FolderIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z" />
    </svg>
  );
}

function FolderView({ roots, renderGroup }: { roots: VaultFolder[]; renderGroup: (group: VaultGroup) => ReactNode }) {
  const t = useTranslations("Providers");
  const [path, setPath] = useState<string[]>([]);
  const trail = folderTrail(roots, path);
  const current = trail.at(-1);
  const folders = current ? current.folders : roots;

  return (
    <div className="flex flex-col gap-3">
      {trail.length > 0 ? (
        <nav aria-label={t("vault.path")} className="flex flex-wrap items-center gap-1 text-sm">
          <button type="button" onClick={() => setPath([])} className="min-h-11 font-semibold" style={{ color: "var(--primary-strong, var(--primary))" }}>
            {t("vault.all")}
          </button>
          {trail.map((folder, index) => (
            <span key={folder.id} className="flex items-center gap-1">
              <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
              {index === trail.length - 1 ? (
                <span aria-current="location" className="font-semibold" style={{ color: "var(--text)" }}>
                  <FolderName folder={folder} />
                </span>
              ) : (
                <button
                  type="button"
                  onClick={() => setPath(path.slice(0, index + 1))}
                  className="min-h-11 font-semibold"
                  style={{ color: "var(--primary-strong, var(--primary))" }}
                >
                  <FolderName folder={folder} />
                </button>
              )}
            </span>
          ))}
        </nav>
      ) : null}
      {folders.length > 0 ? (
        <ul className="grid grid-cols-2 gap-2 sm:grid-cols-3">
          {folders.map((folder) => (
            <li key={folder.id}>
              <button
                type="button"
                onClick={() => setPath([...trail.map((item) => item.id), folder.id])}
                className="flex min-h-20 w-full flex-col items-start justify-between gap-2 rounded-2xl p-3 text-start"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
              >
                <span style={{ color: "var(--dim)" }}>
                  <FolderIcon />
                </span>
                <span className="w-full truncate text-sm font-bold">
                  <FolderName folder={folder} />
                </span>
                <span className="text-xs" style={{ color: "var(--dim)" }}>{t("vault.count", { count: folder.count })}</span>
              </button>
            </li>
          ))}
        </ul>
      ) : null}
      {current && current.groups.length > 0 ? <ul className="grid gap-3 lg:grid-cols-2">{current.groups.map(renderGroup)}</ul> : null}
    </div>
  );
}

function TreeView({ roots, renderGroup }: { roots: VaultFolder[]; renderGroup: (group: VaultGroup) => ReactNode }) {
  const t = useTranslations("Providers");
  // Like an OS tree, everything starts collapsed.
  const [open, setOpen] = useState<Set<string>>(new Set());
  const toggle = (id: string) =>
    setOpen((current) => {
      const next = new Set(current);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  function level(folders: VaultFolder[], depth: number): ReactNode {
    return folders.map((folder) => {
      const expanded = open.has(folder.id);
      return (
        <li key={folder.id} role="treeitem" aria-expanded={expanded} aria-selected={false}>
          <button
            type="button"
            onClick={() => toggle(folder.id)}
            className="flex min-h-11 w-full items-center gap-2 rounded-xl pe-2 text-start text-sm font-semibold"
            style={{ paddingInlineStart: `${depth * 1.25 + 0.5}rem`, color: "var(--text)" }}
          >
            <span aria-hidden="true" className="w-3 text-xs" style={{ color: "var(--dim)" }}>{expanded ? "▾" : "▸"}</span>
            <span style={{ color: "var(--dim)" }}>
              <FolderIcon />
            </span>
            <span className="min-w-0 grow truncate">
              <FolderName folder={folder} />
            </span>
            <span className="text-xs tabular-nums" style={{ color: "var(--dim)" }}>{folder.count}</span>
          </button>
          {expanded ? (
            <ul role="group">
              {level(folder.folders, depth + 1)}
              {folder.groups.length > 0 ? (
                <li role="none" style={{ paddingInlineStart: `${(depth + 1) * 1.25 + 0.5}rem` }} className="py-2">
                  <ul className="grid gap-3 lg:grid-cols-2">{folder.groups.map(renderGroup)}</ul>
                </li>
              ) : null}
            </ul>
          ) : null}
        </li>
      );
    });
  }

  return (
    <ul role="tree" aria-label={t("vault.tree")} className="rounded-2xl p-1" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      {level(roots, 0)}
    </ul>
  );
}
