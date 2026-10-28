import Link from "next/link";
import type { ButtonHTMLAttributes, CSSProperties, ReactNode } from "react";

/**
 * The one back arrow of the app. Back links and back buttons draw it here and
 * never in their label, so a translated "Users" can't come with an arrow of its
 * own and show two (back-link-guard.test.ts keeps it that way). It points the
 * way the page goes back: mirrored in right-to-left languages.
 */
export function BackArrow() {
  return (
    <span aria-hidden="true" className="inline-block rtl:-scale-x-100">
      ←
    </span>
  );
}

const DEFAULT_STYLE: CSSProperties = { color: "var(--primary)" };

type Look = {
  /** Replaces the default size and weight; the arrow and its spacing stay. */
  className?: string;
  style?: CSSProperties;
  children: ReactNode;
};

/** «← Χρήστες»: a link back to the page this one sits under. */
export function BackLink({ href, className, style, children }: Look & { href: string }) {
  return (
    <Link href={href} className={["inline-flex min-w-0 items-center justify-center gap-1", className ?? "min-h-11 text-sm font-semibold"].join(" ")} style={style ?? DEFAULT_STYLE}>
      <BackArrow />
      <span className="truncate">{children}</span>
    </Link>
  );
}

/** A back step that isn't a page: a wizard's previous step, router.back(), a sub-view. */
export function BackButton({
  className,
  style,
  children,
  type = "button",
  ...button
}: Look & Omit<ButtonHTMLAttributes<HTMLButtonElement>, "className" | "style" | "children">) {
  return (
    <button type={type} {...button} className={["inline-flex min-w-0 items-center justify-center gap-1", className ?? "min-h-11 text-sm font-semibold"].join(" ")} style={style ?? DEFAULT_STYLE}>
      <BackArrow />
      <span className="truncate">{children}</span>
    </button>
  );
}
