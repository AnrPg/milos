import type { Metadata } from "next";
import { QueryProvider } from "@/components/query-provider";
import { RealtimeSyncBridge } from "@/components/realtime-sync-bridge";
import { SessionProvider } from "@/components/session-provider";
import { ServiceWorkerBootstrap } from "@/components/service-worker-bootstrap";
import { ThemeProvider } from "@/components/theme-provider";
import { TopNav } from "@/components/TopNav";
import "./globals.css";

export const metadata: Metadata = {
  title: "Milos Training",
  description: "Gym scheduling, athlete programming, and workout execution.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="h-full antialiased">
      <body className="min-h-full flex flex-col" style={{ background: "var(--bg)" }}>
        <QueryProvider>
          <ThemeProvider>
            <SessionProvider>
              <RealtimeSyncBridge />
              <ServiceWorkerBootstrap />
              <TopNav />
              {children}
            </SessionProvider>
          </ThemeProvider>
        </QueryProvider>
      </body>
    </html>
  );
}
