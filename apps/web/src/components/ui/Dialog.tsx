"use client";

import { useId, useRef, type CSSProperties, type FormEvent, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { useTranslations } from "next-intl";

import { useHideBottomNav } from "@/components/nav/bottom-nav-visibility";
import { useModalFocusTrap } from "@/hooks/useModalFocusTrap";
import type { GuideAnchor } from "@/lib/guides/anchors";

export type DialogSize = "sm" | "md" | "lg" | "xl" | "2xl" | "3xl" | "5xl" | "full";

/**
 * How the dialog sits on screen:
 * - "center": a card in the middle, on phones too.
 * - "sheet": a bottom sheet on phones, a centred card from `sm` up.
 * - "drawer": a full-height panel on the end edge (full screen on phones).
 * - "panel": a bottom sheet on phones, a full-height end drawer from `md` up.
 * - "screen": the whole screen on phones (a flow with its own steps), a
 *   centred card from `sm` up.
 */
export type DialogVariant = "center" | "sheet" | "drawer" | "panel" | "screen";

export type DialogLayer = "drawer" | "modal" | "fullscreen" | "toast";

const SIZE: Record<DialogSize, string> = {
  sm: "sm:max-w-sm",
  md: "sm:max-w-md",
  lg: "sm:max-w-lg",
  xl: "sm:max-w-xl",
  "2xl": "sm:max-w-2xl",
  "3xl": "sm:max-w-3xl",
  "5xl": "sm:max-w-5xl",
  full: "sm:max-w-[min(96rem,100%)]",
};

const DRAWER_SIZE: Record<DialogSize, string> = {
  sm: "md:max-w-sm",
  md: "md:max-w-md",
  lg: "md:max-w-lg",
  xl: "md:max-w-xl",
  "2xl": "md:max-w-2xl",
  "3xl": "md:max-w-3xl",
  "5xl": "md:max-w-5xl",
  full: "",
};

const LAYER: Record<DialogLayer, string> = {
  drawer: "var(--z-drawer)",
  modal: "var(--z-modal)",
  fullscreen: "var(--z-fullscreen)",
  toast: "var(--z-toast)",
};

/**
 * The one dialog shell of the app (ADR-177). Every modal, bottom sheet and
 * side drawer renders through it so that, on any screen size:
 * - it never grows past the dynamic viewport (100dvh, safe areas included);
 * - the header and footer stay put while only the body scrolls, so the
 *   close, cancel and save actions are always reachable;
 * - it portals into <body> on the modal layer, above the nav and every card;
 * - focus is trapped, Escape and the backdrop close it, and the page behind
 *   does not scroll.
 *
 * Pass `onSubmit` to make the panel a <form>: footer buttons with
 * type="submit" then submit it and Enter works in every field.
 */
export function Dialog({
  onClose,
  title,
  eyebrow,
  description,
  ariaLabel,
  headerActions,
  children,
  footer,
  footerStart,
  size = "lg",
  variant = "sheet",
  layer = "modal",
  dismissible = true,
  showClose = true,
  closeLabel,
  bare = false,
  plainBody = false,
  onSubmit,
  panelClassName = "",
  bodyClassName = "",
  panelStyle,
  labelledBy,
  titleId: titleIdProp,
  testId,
  guide,
}: {
  onClose: () => void;
  title?: ReactNode;
  eyebrow?: ReactNode;
  description?: ReactNode;
  /** Accessible name; overrides the visible title as the dialog's name. */
  ariaLabel?: string;
  /** Extra controls next to the close button. */
  headerActions?: ReactNode;
  children: ReactNode;
  /** Primary actions, aligned to the end and always visible. */
  footer?: ReactNode;
  /** Secondary footer content on the start side (a hint, a delete link). */
  footerStart?: ReactNode;
  size?: DialogSize;
  variant?: DialogVariant;
  layer?: DialogLayer;
  /** False while saving: the backdrop and Escape no longer close it. */
  dismissible?: boolean;
  showClose?: boolean;
  /** The close button's accessible name; defaults to Common.close. */
  closeLabel?: string;
  /** The children own the panel's layout and scrolling (no header/body/footer). */
  bare?: boolean;
  /** Keep the header and footer but let the children own the body's scrolling. */
  plainBody?: boolean;
  onSubmit?: (event: FormEvent<HTMLFormElement>) => void;
  panelClassName?: string;
  bodyClassName?: string;
  panelStyle?: CSSProperties;
  /** Id of an element inside the children that names the dialog. */
  labelledBy?: string;
  /** A fixed id for the title element (tests and aria references). */
  titleId?: string;
  testId?: string;
  /** The walkthrough anchor of the panel (ADR-193), e.g. "events.wizard". */
  guide?: GuideAnchor;
}) {
  const generatedId = useId();
  const titleId = titleIdProp ?? `${generatedId}-title`;
  const descriptionId = `${generatedId}-description`;
  const panelRef = useModalFocusTrap<HTMLElement>(() => {
    if (dismissible) onClose();
  });
  const pressStartedOnBackdrop = useRef(false);
  // The member app's floating bottom bar steps aside while a dialog is open.
  useHideBottomNav();

  if (typeof document === "undefined") return null;

  const isDrawer = variant === "drawer";
  const isScreen = variant === "screen";
  const rootLayout = isDrawer
    ? "items-stretch justify-end"
    : isScreen
      ? "items-stretch justify-center sm:items-center sm:p-6"
    : variant === "panel"
      ? "items-end justify-center pt-[max(0.75rem,env(safe-area-inset-top))] md:items-stretch md:justify-end md:pt-0"
      : variant === "sheet"
      ? "items-end justify-center pt-[max(0.75rem,env(safe-area-inset-top))] sm:items-center sm:p-6"
      : "items-center justify-center p-3 pt-[max(0.75rem,env(safe-area-inset-top))] sm:p-6";
  const panelShape = isDrawer
    ? `h-full ${DRAWER_SIZE[size]} border-s`
    : isScreen
      ? `h-full sm:h-auto sm:max-h-full sm:rounded-[1.75rem] sm:border ${SIZE[size]}`
    : variant === "panel"
      ? `max-h-full rounded-t-[1.75rem] border md:h-full md:rounded-none md:border-0 md:border-s ${DRAWER_SIZE[size]}`
      : variant === "sheet"
      ? `max-h-full rounded-t-[1.75rem] sm:rounded-[1.75rem] border ${SIZE[size]}`
      : `max-h-full rounded-[1.75rem] border ${SIZE[size]}`;
  const padsBottomSafeArea = variant !== "center";

  const hasHeader = !bare && (title || eyebrow || description || showClose || headerActions);
  const PanelTag = onSubmit ? "form" : "section";

  const panel = (
    <PanelTag
      ref={panelRef as never}
      role="dialog"
      aria-modal="true"
      aria-label={ariaLabel}
      aria-labelledby={ariaLabel ? undefined : title ? titleId : labelledBy}
      aria-describedby={description ? descriptionId : undefined}
      tabIndex={-1}
      data-testid={testId}
      data-guide={guide}
      onSubmit={onSubmit}
      onClick={(event) => event.stopPropagation()}
      className={`relative flex min-h-0 w-full flex-col outline-none ${/\boverflow-/.test(panelClassName) ? "" : "overflow-hidden"} ${
        // A bare drawer covers the whole screen: keep its own header below the notch.
        bare && isDrawer ? "pt-[env(safe-area-inset-top)]" : ""
      } ${panelShape} ${panelClassName}`}
      style={{
        background: "var(--panel)",
        borderColor: "var(--border)",
        color: "var(--text)",
        boxShadow: "var(--shadow-lg)",
        ...panelStyle,
      }}
    >
      {bare ? (
        children
      ) : (
        <>
          {variant === "sheet" || variant === "panel" ? (
            <div className={`flex shrink-0 justify-center pt-2.5 ${variant === "panel" ? "md:hidden" : "sm:hidden"}`} aria-hidden="true">
              <span className="h-1 w-10 rounded-full" style={{ background: "var(--border)" }} />
            </div>
          ) : null}
          {hasHeader ? (
            <header
              className={`flex shrink-0 items-start justify-between gap-3 px-5 pb-3 sm:px-6 ${
                isDrawer ? "pt-[max(1rem,env(safe-area-inset-top))]" : isScreen ? "pt-[max(1rem,env(safe-area-inset-top))] sm:pt-5" : "pt-4 sm:pt-5"
              }`}
            >
              <div className="min-w-0 flex-1">
                {eyebrow ? (
                  <p className="text-xs font-semibold uppercase tracking-[0.2em]" style={{ color: "var(--primary)" }}>
                    {eyebrow}
                  </p>
                ) : null}
                {title ? (
                  <h2 id={titleId} className={`${eyebrow ? "mt-1.5 " : ""}text-xl font-semibold tracking-tight sm:text-2xl`}>
                    {title}
                  </h2>
                ) : null}
                {description ? (
                  <div id={descriptionId} className="mt-1.5 text-sm" style={{ color: "var(--text-soft)" }}>
                    {description}
                  </div>
                ) : null}
              </div>
              {headerActions || showClose ? (
                <div className="flex shrink-0 items-center gap-1">
                  {headerActions}
                  {showClose ? (
                    closeLabel ? (
                      <CloseButton label={closeLabel} onClick={onClose} disabled={!dismissible} />
                    ) : (
                      <TranslatedCloseButton onClick={onClose} disabled={!dismissible} />
                    )
                  ) : null}
                </div>
              ) : null}
            </header>
          ) : null}
          {plainBody ? (
            <div className={`flex min-h-0 flex-1 flex-col ${bodyClassName}`}>{children}</div>
          ) : (
            <div
              className={`min-h-0 flex-1 overflow-y-auto overscroll-contain px-5 sm:px-6 ${footer || footerStart ? "pb-4" : padsBottomSafeArea ? "pb-[max(1.25rem,env(safe-area-inset-bottom))]" : "pb-5"} ${hasHeader ? "" : "pt-5"} ${bodyClassName}`}
            >
              {children}
            </div>
          )}
          {footer || footerStart ? (
            <footer
              className={`flex shrink-0 flex-wrap items-center justify-end gap-2 border-t px-5 pt-3 sm:px-6 ${padsBottomSafeArea ? "pb-[max(0.75rem,env(safe-area-inset-bottom))]" : "pb-3"}`}
              style={{ borderColor: "var(--border)", background: "inherit" }}
            >
              {footerStart ? <div className="me-auto flex min-w-0 items-center gap-2">{footerStart}</div> : null}
              {footer}
            </footer>
          ) : null}
        </>
      )}
    </PanelTag>
  );

  return createPortal(
    <div
      role="presentation"
      className={`fixed inset-0 flex ${rootLayout}`}
      style={{
        zIndex: LAYER[layer],
        background: "var(--scrim)",
      }}
      onPointerDown={(event) => {
        pressStartedOnBackdrop.current = event.target === event.currentTarget;
      }}
      onClick={(event) => {
        // Only a press that starts and ends on the backdrop closes it, so
        // selecting text in a field and releasing outside keeps the dialog.
        if (event.target === event.currentTarget && pressStartedOnBackdrop.current && dismissible) onClose();
        pressStartedOnBackdrop.current = false;
      }}
    >
      {panel}
    </div>,
    document.body,
  );
}

function TranslatedCloseButton(props: { onClick: () => void; disabled: boolean }) {
  const common = useTranslations("Common");
  return <CloseButton label={common("close")} {...props} />;
}

function CloseButton({ label, onClick, disabled }: { label: string; onClick: () => void; disabled: boolean }) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-label={label}
      data-dialog-close=""
      className="-me-2 -mt-1 grid h-11 w-11 place-items-center rounded-full text-2xl leading-none transition-colors hover:bg-[color-mix(in_srgb,var(--text)_8%,transparent)] disabled:opacity-40"
      style={{ color: "var(--text-soft)" }}
    >
      <span aria-hidden="true">×</span>
    </button>
  );
}

/** The standard footer and inline buttons for dialogs. */
export function DialogButton({
  children,
  onClick,
  tone = "secondary",
  disabled,
  type = "button",
  form,
  className = "",
  testId,
}: {
  children: ReactNode;
  onClick?: () => void;
  tone?: "primary" | "secondary" | "danger" | "ghost";
  disabled?: boolean;
  type?: "button" | "submit";
  form?: string;
  className?: string;
  testId?: string;
}) {
  const style: CSSProperties =
    tone === "primary"
      ? { background: "var(--primary)", color: "var(--primary-contrast)" }
      : tone === "danger"
        ? { background: "var(--danger)", color: "var(--danger-contrast)" }
        : tone === "ghost"
          ? { background: "transparent", color: "var(--text-soft)" }
          : { background: "var(--panel-raised)", color: "var(--text)", border: "1px solid var(--border)" };
  return (
    <button
      type={type}
      form={form}
      onClick={onClick}
      disabled={disabled}
      data-testid={testId}
      className={`min-h-11 rounded-full px-5 text-sm font-semibold transition-opacity disabled:opacity-50 ${className}`}
      style={style}
    >
      {children}
    </button>
  );
}
