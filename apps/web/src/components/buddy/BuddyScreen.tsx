import type { ReactNode } from "react";

/** The frame of Buddy's screens. */
export function BuddyScreen({ children }: { children: ReactNode }) {
  return (
    <main className="min-h-screen px-4 py-6 md:px-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto flex max-w-2xl flex-col gap-4">{children}</div>
    </main>
  );
}
