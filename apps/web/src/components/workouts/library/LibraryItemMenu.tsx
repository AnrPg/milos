"use client";

import { useRef } from "react";

import { Popover } from "@/components/ui/Popover";

export type LibraryMenuAction = {
  key: string;
  icon: string;
  label: string;
  onSelect: () => void;
  danger?: boolean;
  disabled?: boolean;
};

const MENU_WIDTH = 224;

/**
 * "⋯" actions menu for a library file or folder, like an OS context menu.
 * Controlled so right-clicking the item can open it and only one menu is open at a time.
 * The menu is a Popover, so it stays on screen and above every card.
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
      <Popover
        anchorRef={triggerRef}
        open={open}
        onClose={() => onOpenChange(false)}
        align="end"
        width={MENU_WIDTH}
        role="menu"
        ariaLabel={label}
        className="rounded-xl py-1 shadow-2xl"
        style={{ background: "var(--panel-raised)", border: "1px solid var(--border-strong)" }}
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
      </Popover>
    </div>
  );
}
