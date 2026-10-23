import type { ReactNode } from "react";

/** Small shared pieces of Εγώ › Πληρωμές. */

export function Row({ title, detail, end }: { title: ReactNode; detail?: ReactNode; end?: ReactNode }) {
  return (
    <li className="flex min-w-0 items-center justify-between gap-3 py-2.5" style={{ borderBottom: "1px solid var(--border)" }}>
      <div className="flex min-w-0 flex-1 flex-col">
        <span className="break-words text-sm font-semibold" style={{ color: "var(--text)" }}>{title}</span>
        {detail ? <span className="break-words text-xs" style={{ color: "var(--dim)" }}>{detail}</span> : null}
      </div>
      {end ? <div className="shrink-0">{end}</div> : null}
    </li>
  );
}

export function Detail({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="flex min-w-0 items-center justify-between gap-3">
      <dt style={{ color: "var(--dim)" }}>{label}</dt>
      <dd className="min-w-0 break-words text-end font-semibold" style={{ color: "var(--text)" }}>{value}</dd>
    </div>
  );
}

export function Empty({ children }: { children: ReactNode }) {
  return <p className="text-sm" style={{ color: "var(--dim)" }}>{children}</p>;
}

/** A compact group with a small heading, inside one segment card. */
export function Group({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="min-w-0">
      <h3 className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{title}</h3>
      <ul className="flex flex-col">{children}</ul>
    </section>
  );
}
