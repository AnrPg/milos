import type { CSSProperties, ReactNode } from "react";

/**
 * ADR-195: every error the app shows the person — a failed request, invalid
 * credentials, a field that does not validate — is this one red notice, so
 * errors read the same everywhere and never borrow the action blue.
 *
 * - "banner" (default): a prominent box for form- and page-level errors.
 * - "field": the compact box under one input.
 * - "text": icon and red text without a box, for tight rows and cells.
 *
 * Colours come only from the theme's danger tokens (docs/brand/THEME.md).
 */
export type ErrorNoticeVariant = "banner" | "field" | "text";

type ErrorNoticeProps = {
  children: ReactNode;
  /** A short bold first line above the message (banner only). */
  title?: ReactNode;
  variant?: ErrorNoticeVariant;
  /** A retry or dismiss control shown at the end of a banner. */
  action?: ReactNode;
  id?: string;
  className?: string;
  style?: CSSProperties;
  /** "polite" for errors that refresh in the background; "assertive" (role alert) otherwise. */
  live?: "assertive" | "polite";
};

const BOX_STYLE: CSSProperties = {
  background: "var(--danger-surface)",
  border: "1px solid var(--danger-border)",
  color: "var(--danger-strong)",
};

const LAYOUT: Record<ErrorNoticeVariant, string> = {
  banner: "flex items-start gap-3 rounded-2xl px-4 py-3 text-sm font-medium leading-5",
  field: "flex items-start gap-2 rounded-xl px-3 py-2 text-xs font-medium leading-5",
  text: "flex items-start gap-1.5 text-sm font-semibold leading-5",
};

export function ErrorNotice({
  children,
  title,
  variant = "banner",
  action,
  id,
  className,
  style,
  live = "assertive",
}: ErrorNoticeProps) {
  const boxed = variant !== "text";

  return (
    <div
      id={id}
      role={live === "assertive" ? "alert" : "status"}
      aria-live={live}
      data-error-notice={variant}
      className={[LAYOUT[variant], className].filter(Boolean).join(" ")}
      style={{ ...(boxed ? BOX_STYLE : { color: "var(--danger-strong)" }), ...style }}
    >
      <ErrorIcon className={variant === "banner" ? "mt-0.5 h-4 w-4 shrink-0" : "mt-0.5 h-3.5 w-3.5 shrink-0"} />
      <div className="min-w-0 flex-1 break-words">
        {title && variant === "banner" ? <p className="font-semibold">{title}</p> : null}
        {children}
      </div>
      {action && variant === "banner" ? <div className="shrink-0">{action}</div> : null}
    </div>
  );
}

/**
 * ADR-205: the plain-language reason under a wrong field. Give the field
 * `aria-invalid` and `aria-describedby={id}` (see `invalidFieldProps`).
 * Renders nothing without a message, so it can sit under every field.
 */
export function FieldError({ id, children }: { id: string; children?: ReactNode }) {
  if (!children) return null;
  return (
    <ErrorNotice id={id} variant="text" className="mt-1.5 text-xs font-medium" live="polite">
      {children}
    </ErrorNotice>
  );
}

function ErrorIcon({ className }: { className: string }) {
  return (
    <svg aria-hidden="true" viewBox="0 0 20 20" fill="none" className={className}>
      <circle cx="10" cy="10" r="8.25" stroke="currentColor" strokeWidth="1.5" />
      <path d="M10 5.75v5.5" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" />
      <circle cx="10" cy="14.1" r="1.05" fill="currentColor" />
    </svg>
  );
}
