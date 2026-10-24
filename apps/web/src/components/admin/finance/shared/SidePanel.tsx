"use client";

import {useUiTranslations} from "@/i18n/ui";
import type { ReactNode } from "react";

import { Dialog } from "@/components/ui/Dialog";
import type { GuideAnchor } from "@/lib/guides/anchors";

/** An end-edge detail drawer (full screen on phones) on the shared dialog shell. */
export function SidePanel({
  title,
  subtitle,
  onClose,
  children,
  footer,
  width = "md:max-w-[520px]",
  bare = false,
  guide,
}: {
  title: string;
  subtitle?: string;
  onClose: () => void;
  children: ReactNode;
  footer?: ReactNode;
  width?: string;
  /** Children manage their own scrolling and footer (for example a wizard). */
  bare?: boolean;
  /** A walkthrough anchor of the panel (ADR-193). */
  guide?: GuideAnchor;
}) {
  const i18n = useUiTranslations();

  return (
    <Dialog
      onClose={onClose}
      guide={guide}
      eyebrow={<span style={{ color: "var(--dim)" }}>{subtitle ?? i18n("detail7c9a7c0")}</span>}
      title={title}
      variant="drawer"
      layer="drawer"
      size="full"
      panelClassName={width}
      panelStyle={{ background: "var(--bg)" }}
      plainBody={bare}
      bodyClassName={bare ? "" : "space-y-6 pt-1"}
      footer={footer ? <div className="w-full">{footer}</div> : undefined}
    >
      {children}
    </Dialog>
  );
}
