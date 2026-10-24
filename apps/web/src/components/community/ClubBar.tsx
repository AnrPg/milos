"use client";

import Link from "next/link";
import type { ReactNode } from "react";
import { useTranslations } from "next-intl";

import type { CommunityClub } from "@/api/community";
import { clubInitials } from "@/components/community/community";
import { NavIcon } from "@/components/nav/NavIcons";

/**
 * The club bar (vision §7.1): Όλα, then one bubble per club (a bubble opens
 * the club page), then «Βρες» (a magnifying glass) for open clubs, groups
 * and people (board 7 Q7).
 */
export function ClubBar({
  clubs,
  activeClubId,
  findActive = false,
}: {
  clubs: CommunityClub[];
  activeClubId?: string | null;
  findActive?: boolean;
}) {
  const t = useTranslations("Community");
  const tClubs = useTranslations("Clubs");
  return (
    // A horizontal scroller clips vertically too: py-1.5 leaves room for the
    // active ring (2px outline + 2px offset) so no bubble is cut.
    <nav aria-label={t("clubBar")} className="-mx-4 overflow-x-auto px-4 py-1.5">
      <ul className="flex gap-3">
        <Bubble href="/" label={t("all")} initials={t("allShort")} active={!activeClubId && !findActive} />
        {clubs.map((club) => (
          <Bubble
            key={club.id}
            href={`/clubs/${club.id}`}
            label={club.name}
            initials={clubInitials(club.name)}
            logo={club.logo_url}
            active={club.id === activeClubId}
          />
        ))}
        <Bubble href="/clubs/find" label={tClubs("find")} initials={<NavIcon name="search" size={22} strokeWidth={2} />} active={findActive} dashed />
      </ul>
    </nav>
  );
}

function Bubble({
  href,
  label,
  initials,
  logo,
  active,
  dashed,
}: {
  href: string;
  label: string;
  initials: ReactNode;
  logo?: string | null;
  active: boolean;
  dashed?: boolean;
}) {
  return (
    <li className="shrink-0">
      <Link href={href} aria-current={active ? "page" : undefined} className="flex w-16 flex-col items-center gap-1">
        <span
          className="flex h-14 w-14 items-center justify-center overflow-hidden rounded-full text-sm font-extrabold"
          style={{
            background: "var(--panel-raised)",
            color: "var(--text)",
            outline: active ? "2px solid var(--primary)" : `1px ${dashed ? "dashed" : "solid"} var(--border)`,
            outlineOffset: 2,
          }}
        >
          {logo ? (
            // eslint-disable-next-line @next/next/no-img-element -- gym-uploaded media origin
            <img src={logo} alt="" className="h-full w-full object-cover" />
          ) : (
            initials
          )}
        </span>
        <span className="w-full truncate text-center text-xs" style={{ color: active ? "var(--text)" : "var(--dim)" }}>
          {label}
        </span>
      </Link>
    </li>
  );
}
