"use client";

import Link from "next/link";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { logWellnessEntry, WELLNESS_KEY } from "@/api/wellness";
import { useSession } from "@/components/session-provider";

import { glasses, localDate } from "./wellness-model";
import { useWellness, wellnessWindow } from "./WellnessPanel";

/**
 * The compact «Σήμερα» strip on Αρχική (board 14, Q1 «home»): a glass in one
 * tap and the way to Λιγούρα, only for people who use Ευεξία.
 */
export function WellnessStrip() {
  const t = useTranslations("MemberApp.wellness");
  const queryClient = useQueryClient();
  const { tokens } = useSession();
  const today = localDate(new Date());
  const range = wellnessWindow(today, 0);
  const query = useWellness(range.from, range.to);
  const data = query.data;
  // A secondary surface: an unexpected answer hides the strip rather than breaking Αρχική.
  const day = data?.days?.find((entry) => entry.date === today);

  const add = useMutation({
    mutationFn: async () =>
      logWellnessEntry(tokens!.access_token, { kind: "water", value: { ml: data!.preferences.glass_ml } }),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: WELLNESS_KEY }),
  });

  if (!data?.consented || !day || !data.preferences) return null;
  const water = !data.preferences.hidden_items.includes("water");
  const { filled, goal } = glasses(day.water);

  return (
    <section
      aria-label={t("eyebrow")}
      className="flex items-center gap-3 rounded-3xl px-4 py-3"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      data-testid="wellness-strip"
    >
      {water ? (
        <>
          <Link href="/journal/wellbeing#today" className="min-w-0 grow">
            <span className="block text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{t("item.water")}</span>
            <span className="block text-sm font-extrabold tabular-nums" style={{ color: "var(--text)" }}>
              {t("water.glasses", { filled, goal })}
            </span>
          </Link>
          <button
            type="button"
            onClick={() => add.mutate()}
            disabled={add.isPending}
            className="min-h-11 rounded-2xl px-4 text-sm font-extrabold disabled:opacity-60"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {t("water.add")}
          </button>
        </>
      ) : (
        <Link href="/journal/wellbeing#today" className="grow text-sm font-bold" style={{ color: "var(--text)" }}>
          {t("eyebrow")}
        </Link>
      )}
      <Link
        href="/journal/wellbeing?craving=new"
        className="min-h-11 rounded-2xl px-3 py-2 text-sm font-semibold"
        style={{ border: "1px solid var(--border)", color: "var(--text)" }}
      >
        {t("item.cravings")}
      </Link>
    </section>
  );
}
