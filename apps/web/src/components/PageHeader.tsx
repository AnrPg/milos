import type { ReactNode } from "react";

type Props = {
  title: ReactNode;
  actions?: ReactNode;
};

/**
 * Static page heading. Replaces the former auto-hiding introduction banner:
 * every page shows only its title, optionally followed by compact actions.
 */
export function PageHeader({ title, actions }: Props) {
  return (
    <header className="flex flex-wrap items-center justify-between gap-3">
      <h1
        className="min-w-0 text-2xl font-semibold tracking-tight md:text-3xl"
        style={{ color: "var(--text)" }}
      >
        {title}
      </h1>
      {actions ? <div className="flex flex-wrap items-center gap-2">{actions}</div> : null}
    </header>
  );
}

export const pageHeaderActionClass = "rounded-xl px-4 py-2 text-sm font-semibold text-center";
