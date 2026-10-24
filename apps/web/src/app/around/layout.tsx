import { Suspense, type ReactNode } from "react";

import { AroundProvider } from "@/components/around/use-around";

/** Γύρω μου keeps one filter and starting point while you move around it (ADR-154). */
export default function AroundLayout({ children }: { children: ReactNode }) {
  return (
    <Suspense>
      <AroundProvider>{children}</AroundProvider>
    </Suspense>
  );
}
