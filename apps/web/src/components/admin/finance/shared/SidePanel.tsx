"use client";

import {useUiTranslations} from "@/i18n/ui";
import type { ReactNode } from "react";

import { Dialog } from "@/components/ui/Dialog";

/** An end-edge detail drawer (full screen on phones) on the shared dialog shell. */
export function SidePanel({
  title,
  subtitle,
  onClose,
  children,
  footer,
  width = "md:max-w-[520px]",
  bare = false,
}: {
  title: string;
  subtitle?: string;
  onClose: () => void;
  children: ReactNode;
  footer?: ReactNode;
  width?: string;
  /** Children manage their own scrolling and footer (for example a wizard). */
  bare?: boolean;
}) {
  const i18n = useUiTranslations();

  return (
    <Dialog
      onClose={onClose}
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
