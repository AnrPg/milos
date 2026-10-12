"use client";

import { useEffect, useLayoutEffect, useRef, useState } from "react";

export type LibraryMenuAction = {
  key: string;
  icon: string;
  label: string;
  onSelect: () => void;
  danger?: boolean;
  disabled?: boolean;
};

const MENU_WIDTH = 224;
const VIEWPORT_MARGIN = 8;

/**
 * "⋯" actions menu for a library file or folder, like an OS context menu.
 * Controlled so right-clicking the item can open it and only one menu is open at a time.
 * The menu is positioned against the viewport so it never spills off-screen.
 */
export function LibraryItemMenu({
  label,
  actions,
  open,
  onOpenChange,
  className = "",
}: {
  label: string;
  actions: LibraryMenuAction[];
  open: boolean;
  onOpenChange: (open: boolean) => void;
  className?: string;
}) {
  const triggerRef = useRef<HTMLButtonElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const [position, setPosition] = useState<{ top: number; left: number } | null>(null);

  useLayoutEffect(() => {
    if (!open || !triggerRef.current) return;
    const rect = triggerRef.current.getBoundingClientRect();
    const menuHeight = menuRef.current?.offsetHeight ?? actions.length * 40 + 8;
    const left = Math.min(Math.max(rect.right - MENU_WIDTH, VIEWPORT_MARGIN), window.innerWidth - MENU_WIDTH - VIEWPORT_MARGIN);
    const below = rect.bottom + 4;
    const top = below + menuHeight > window.innerHeight - VIEWPORT_MARGIN ? Math.max(rect.top - menuHeight - 4, VIEWPORT_MARGIN) : below;
    setPosition({ top, left });
  }, [actions.length, open]);

  useEffect(() => {
    if (!open) return;
    function handlePointerDown(event: PointerEvent) {
      const target = event.target as Node;
      if (!menuRef.current?.contains(target) && !triggerRef.current?.contains(target)) onOpenChange(false);
    }
    function handleKey(event: KeyboardEvent) {
      if (event.key === "Escape") onOpenChange(false);
    }
    function handleViewportChange() {
      onOpenChange(false);
    }
    document.addEventListener("pointerdown", handlePointerDown);
    document.addEventListener("keydown", handleKey);
    window.addEventListener("resize", handleViewportChange);
    window.addEventListener("scroll", handleViewportChange, true);
    return () => {
      document.removeEventListener("pointerdown", handlePointerDown);
      document.removeEventListener("keydown", handleKey);
      window.removeEventListener("resize", handleViewportChange);
      window.removeEventListener("scroll", handleViewportChange, true);
    };
  }, [onOpenChange, open]);

  return (
    <div className={className} onClick={(event) => event.stopPropagation()}>
      <button
        ref={triggerRef}
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label={label}
        className="grid h-7 w-7 place-items-center rounded-full text-sm leading-none"
        style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
        onClick={() => onOpenChange(!open)}
      >
        ⋯
      </button>
      {open ? (
        <div
          ref={menuRef}
          role="menu"
          aria-label={label}
          className="fixed z-[90] overflow-hidden rounded-xl py-1 shadow-2xl"
          style={{
            width: MENU_WIDTH,
            top: position?.top ?? -9999,
            left: position?.left ?? -9999,
            background: "var(--panel-raised)",
            border: "1px solid var(--border-strong)",
          }}
        >
          {actions.map((action) => (
            <button
              key={action.key}
              type="button"
              role="menuitem"
              disabled={action.disabled}
              className="flex w-full items-center gap-3 px-3 py-2 text-start text-sm hover:bg-[var(--panel-muted)] disabled:opacity-40"
              style={{ color: action.danger ? "var(--danger)" : "var(--text-soft)" }}
              onClick={() => {
                onOpenChange(false);
                action.onSelect();
              }}
            >
              <span aria-hidden className="w-5 text-center">{action.icon}</span>
              <span className="min-w-0 flex-1 truncate">{action.label}</span>
            </button>
          ))}
        </div>
      ) : null}
    </div>
  );
}
