"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import type { CommunityClub } from "@/api/community";
import { clubInitials } from "@/components/community/community";

/** The club bar (vision §7.1): Όλα, then one bubble per club; a bubble opens the club page. */
export function ClubBar({ clubs, activeClubId }: { clubs: CommunityClub[]; activeClubId?: string | null }) {
  const t = useTranslations("Community");
  return (
    <nav aria-label={t("clubBar")} className="-mx-4 overflow-x-auto px-4">
      <ul className="flex gap-3">
        <Bubble href="/" label={t("all")} initials={t("allShort")} active={!activeClubId} />
        {clubs.map((club) => (
          <Bubble
            key={club.id}
            href={`/clubs/${club.id}`}
            label={club.name}
            initials={clubInitials(club.name)}
            color={club.primary_color}
            logo={club.logo_url}
            active={club.id === activeClubId}
          />
        ))}
      </ul>
    </nav>
  );
}

function Bubble({
  href,
  label,
  initials,
  color,
  logo,
  active,
}: {
  href: string;
  label: string;
  initials: string;
  color?: string | null;
  logo?: string | null;
  active: boolean;
}) {
  return (
    <li className="shrink-0">
      <Link href={href} aria-current={active ? "page" : undefined} className="flex w-16 flex-col items-center gap-1">
        <span
          className="flex h-14 w-14 items-center justify-center overflow-hidden rounded-full text-sm font-extrabold"
          style={{
            background: color ?? "var(--panel-raised)",
            color: color ? "#fff" : "var(--text)",
            outline: active ? "2px solid var(--primary)" : "1px solid var(--border)",
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
