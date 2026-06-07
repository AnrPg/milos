"use client";

import Link from "next/link";

import { useSession } from "@/components/session-provider";

export function AdminHome() {
  const { currentUser, signOut } = useSession();

  return (
    <main className="min-h-screen bg-[linear-gradient(180deg,#fffdf8_0%,#f5ede3_100%)] px-6 py-10 md:px-10 md:py-14">
      <div className="mx-auto max-w-5xl space-y-8">
        <section className="rounded-[2.4rem] border border-black/10 bg-white/85 p-8 shadow-[0_28px_80px_rgba(20,40,29,0.12)]">
          <p className="text-sm font-semibold uppercase tracking-[0.28em] text-accent-strong">Admin</p>
          <h1 className="mt-4 text-4xl font-semibold tracking-tight text-slate-950 md:text-5xl">
            Admin access is live.
          </h1>
          <p className="mt-4 text-base leading-7 text-slate-600">
            Signed in as <span className="font-semibold">{currentUser?.nickname}</span>. Use the links below to reach the
            implemented Phase 2 workout-management surface.
          </p>
        </section>

        <section className="grid gap-4 md:grid-cols-3">
          <Link
            className="rounded-[1.8rem] border border-black/10 bg-white p-6 shadow-[0_20px_60px_rgba(20,40,29,0.08)]"
            href="/admin/workouts"
          >
            <p className="text-sm font-semibold uppercase tracking-[0.24em] text-slate-500">Workout list</p>
            <p className="mt-3 text-xl font-semibold text-slate-950">/admin/workouts</p>
          </Link>

          <Link
            className="rounded-[1.8rem] border border-black/10 bg-white p-6 shadow-[0_20px_60px_rgba(20,40,29,0.08)]"
            href="/admin/workouts/new"
          >
            <p className="text-sm font-semibold uppercase tracking-[0.24em] text-slate-500">Workout creation</p>
            <p className="mt-3 text-xl font-semibold text-slate-950">/admin/workouts/new</p>
          </Link>

          <button
            className="rounded-[1.8rem] border border-[#d95d39]/20 bg-[#d95d39]/10 p-6 text-left shadow-[0_20px_60px_rgba(20,40,29,0.08)]"
            onClick={signOut}
            type="button"
          >
            <p className="text-sm font-semibold uppercase tracking-[0.24em] text-[#a4462c]">Session</p>
            <p className="mt-3 text-xl font-semibold text-[#a4462c]">Log out</p>
          </button>
        </section>
      </div>
    </main>
  );
}
