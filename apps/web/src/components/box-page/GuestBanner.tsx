"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useTranslations } from "next-intl";

import { fetchGuestBoxes } from "@/api/desk-collect";
import { FRESHNESS } from "@/lib/query-policy";

import { Icon } from "./Icon";

export const GUEST_BOXES_KEY = ["account", "guest-boxes"] as const;

/**
 * ADR-272: a guest of the box (made at the desk) sees that they are one, and
 * the next step: becoming a box member through the box's packages page.
 * Who belongs where is `account` data (ADR-215).
 */
export function GuestBanner({ token, box }: { token: string; box: { organization_id: string; slug: string; name: string } }) {
  const t = useTranslations("BoxPage");
  const boxes = useQuery({
    queryKey: GUEST_BOXES_KEY,
    staleTime: FRESHNESS.account,
    queryFn: () => fetchGuestBoxes(token).then((response) => response.boxes),
  });
  const guest = boxes.data?.some((entry) => entry.id === box.organization_id || entry.slug === box.slug);
  if (!guest) return null;
  return (
    <section
      aria-labelledby="box-guest-title"
      className="mx-4 mt-4 flex flex-col gap-3 rounded-3xl p-4 sm:flex-row sm:items-center lg:mx-0"
      style={{
        background: "linear-gradient(135deg, color-mix(in srgb, var(--primary) 22%, var(--panel)), color-mix(in srgb, var(--spark) 14%, var(--panel)))",
        border: "1px solid var(--primary)",
      }}
      data-testid="box-guest-banner"
    >
      <span className="grid h-10 w-10 shrink-0 place-items-center rounded-full" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
        <Icon name="check" size={18} />
      </span>
      <div className="min-w-0 flex-1">
        <h2 id="box-guest-title" className="text-base font-extrabold" style={{ color: "var(--text)" }}>
          {t("guestTitle", { box: box.name })}
        </h2>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("guestBody")}</p>
      </div>
      <Link
        href={`/b/${box.slug}/packages`}
        className="flex min-h-11 shrink-0 items-center justify-center rounded-2xl px-4 text-sm font-bold"
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        data-testid="box-guest-join"
      >
        {t("guestAction")}
      </Link>
    </section>
  );
}
