import type { ReactNode } from "react";
import type { FolderMark } from "@/components/workouts/library/library-folders";

/**
 * Vault icons: a folder shape for folders and a page shape for workouts, each
 * with its mark (emoji, glyph or date) in the middle, so a glance tells
 * folders from files. Every colour comes from the theme variables.
 */

type IconSize = "tile" | "inline";

const FOLDER_BOX: Record<IconSize, string> = { tile: "h-12 w-14", inline: "h-[1.4rem] w-[1.65rem]" };
const FILE_BOX: Record<IconSize, string> = { tile: "h-[3.1rem] w-[2.6rem]", inline: "h-[1.55rem] w-[1.3rem]" };

const FOLDER_BACK = "color-mix(in srgb, var(--primary) 34%, var(--panel-muted))";
const FOLDER_FRONT = "color-mix(in srgb, var(--primary) 18%, var(--panel))";
const PAGE_FILL = "color-mix(in srgb, var(--primary) 12%, var(--panel))";
const PAGE_STROKE = "color-mix(in srgb, var(--primary) 35%, var(--border))";
const PAGE_FOLD = "color-mix(in srgb, var(--primary) 30%, var(--panel-muted))";

export function FolderIcon({ mark, size = "tile", count }: { mark: FolderMark; size?: IconSize; count?: number }) {
  return (
    <span aria-hidden data-icon="folder" className={`relative inline-grid shrink-0 place-items-center ${FOLDER_BOX[size]}`}>
      <svg viewBox="0 0 56 48" className="absolute inset-0 h-full w-full overflow-visible drop-shadow-sm">
        <path fill={FOLDER_BACK} d="M4 8a4 4 0 0 1 4-4h13l5 5h22a4 4 0 0 1 4 4v27a4 4 0 0 1-4 4H8a4 4 0 0 1-4-4z" />
        <path fill={FOLDER_FRONT} d="M4 16a4 4 0 0 1 4-4h40a4 4 0 0 1 4 4v24a4 4 0 0 1-4 4H8a4 4 0 0 1-4-4z" />
      </svg>
      {/* The front flap starts a quarter down, so the mark sits a little below centre. */}
      <span className={`relative grid place-items-center ${size === "tile" ? "mt-[0.45rem]" : "mt-[0.2rem]"}`}>
        <FolderMarkContent mark={mark} size={size} />
      </span>
      {count && count > 0 ? (
        <span className="absolute -bottom-1 -end-2 min-w-5 rounded-full px-1 text-center text-[10px] font-bold leading-4" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
          {count}
        </span>
      ) : null}
    </span>
  );
}

export function WorkoutFileIcon({ emoji, size = "tile", draft = false }: { emoji: string; size?: IconSize; draft?: boolean }) {
  return (
    <span aria-hidden data-icon="file" className={`relative inline-grid shrink-0 place-items-center ${FILE_BOX[size]}`}>
      <svg viewBox="0 0 42 50" className="absolute inset-0 h-full w-full overflow-visible drop-shadow-sm">
        <path fill={PAGE_FILL} stroke={PAGE_STROKE} strokeWidth={1.2} d="M8 2h18l12 12v30a4 4 0 0 1-4 4H8a4 4 0 0 1-4-4V6a4 4 0 0 1 4-4z" />
        <path fill={PAGE_FOLD} d="M26 2v8a4 4 0 0 0 4 4h8z" />
      </svg>
      <span className={`relative leading-none ${size === "tile" ? "mt-1 text-xl" : "mt-[0.15rem] text-[0.7rem]"}`}>{emoji}</span>
      {draft ? (
        <span className="absolute -end-1 -top-1 h-2.5 w-2.5 rounded-full" style={{ background: "var(--warning)", boxShadow: "0 0 0 2px var(--panel)" }} />
      ) : null}
    </span>
  );
}

function FolderMarkContent({ mark, size }: { mark: FolderMark; size: IconSize }): ReactNode {
  const tile = size === "tile";
  switch (mark.kind) {
    case "emoji":
      return <span className={`leading-none ${tile ? "text-xl" : "text-[0.7rem]"}`}>{mark.emoji}</span>;
    case "transfer":
      return <MemberTransferGlyph className={tile ? "h-6 w-6" : "h-[0.85rem] w-[0.85rem]"} />;
    case "date":
      if (!tile) return null;
      return (
        <span className="flex flex-col items-center font-bold leading-none tabular-nums" style={{ color: "var(--text)" }}>
          {mark.caption ? <span className="text-[8px] uppercase tracking-wide" style={{ color: "var(--primary)" }}>{mark.caption}</span> : null}
          <span className={mark.main.length > 3 ? "text-xs" : "text-sm"}>{mark.main}</span>
        </span>
      );
    default:
      return null;
  }
}

/** One person handing over to another: the folder of workouts reworked for a single member. */
export function MemberTransferGlyph({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 24 24" className={className} aria-hidden>
      <circle cx="7.5" cy="6.5" r="3.4" fill="var(--primary)" />
      <path d="M1.5 20.5c0-4 2.7-6.6 6-6.6s6 2.6 6 6.6z" fill="var(--primary)" />
      <circle cx="16.5" cy="6.5" r="3.1" fill="none" stroke="var(--primary)" strokeWidth={1.6} />
      <path d="M11 20.5c0-3.7 2.4-6.1 5.5-6.1s5.5 2.4 5.5 6.1z" fill="none" stroke="var(--primary)" strokeWidth={1.6} />
      <path d="M6 15.6h6v-2.6l4.6 4-4.6 4v-2.6H6z" fill="var(--primary)" stroke="var(--panel)" strokeWidth={1.2} paintOrder="stroke" />
    </svg>
  );
}
