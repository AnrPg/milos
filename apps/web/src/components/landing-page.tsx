"use client";

import Link from "next/link";

import { useSession } from "@/components/session-provider";

export function LandingPage() {
  const { currentUser, rotate, signOut, tokens } = useSession();

  return (
    <main className="min-h-screen bg-[linear-gradient(180deg,#fffdf8_0%,#f5ede3_100%)] px-6 py-10 md:px-10 md:py-14">
      <div className="mx-auto max-w-4xl space-y-8">
        <section className="rounded-[2.4rem] border border-black/10 bg-white/85 p-8 shadow-[0_28px_80px_rgba(20,40,29,0.12)]">
          <p className="text-sm font-semibold uppercase tracking-[0.28em] text-accent-strong">
            Milos Training
          </p>
          <h1 className="mt-4 text-4xl font-semibold tracking-tight text-slate-950 md:text-5xl">
            Logged in.
          </h1>
          <p className="mt-4 text-base leading-7 text-slate-600">
            This is the temporary authenticated landing page for the current phase.
          </p>
        </section>

        <section className="grid gap-6 md:grid-cols-[1fr_auto]">
          <div className="rounded-[2rem] border border-black/10 bg-white/85 p-6 shadow-[0_20px_60px_rgba(20,40,29,0.08)]">
            <p className="text-sm font-semibold uppercase tracking-[0.24em] text-slate-500">Current user</p>
            <dl className="mt-4 space-y-3 text-sm text-slate-700">
              <div className="flex items-center justify-between gap-4">
                <dt>Nickname</dt>
                <dd className="font-semibold">{currentUser?.nickname}</dd>
              </div>
              <div className="flex items-center justify-between gap-4">
                <dt>Role</dt>
                <dd className="font-semibold">{currentUser?.role}</dd>
              </div>
            </dl>
          </div>

          <div className="flex flex-col gap-3">
            {currentUser?.role === "admin" ? (
              <>
                <Link
                  className="rounded-2xl bg-slate-950 px-5 py-3 text-center text-sm font-semibold text-white"
                  href="/admin"
                >
                  Open admin
                </Link>
                <Link
                  className="rounded-2xl border border-black/10 bg-white px-5 py-3 text-center text-sm font-semibold text-slate-700"
                  href="/admin/workouts/new"
                >
                  Create workout
                </Link>
              </>
            ) : null}

            <button
              className="rounded-2xl border border-black/10 bg-white px-5 py-3 text-sm font-semibold text-slate-700 disabled:opacity-50"
              disabled={!tokens}
              onClick={() => void rotate()}
              type="button"
            >
              Refresh session
            </button>

            <button
              className="rounded-2xl border border-[#d95d39]/20 bg-[#d95d39]/10 px-5 py-3 text-sm font-semibold text-[#a4462c]"
              onClick={signOut}
              type="button"
            >
              Log out
            </button>
          </div>
        </section>
      </div>
    </main>
  );
}
