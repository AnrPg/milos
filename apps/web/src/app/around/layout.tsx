import { Suspense, type ReactNode } from "react";

import { AroundProvider } from "@/components/around/use-around";

/** Γύρω μου and its «Δες όλα» pages share one filter and starting point (ADR-154). */
export default function AroundLayout({ children }: { children: ReactNode }) {
  return (
    <Suspense>
      <AroundProvider>{children}</AroundProvider>
    </Suspense>
  );
}
