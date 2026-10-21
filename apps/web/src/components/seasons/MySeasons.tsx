"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";

import {
  MY_SEASONS_KEY,
  cancelSeasonRequest,
  fetchMySeasons,
  memberSeasonAction,
  requestSeasonPlace,
  type MemberSeason,
} from "@/api/seasons";
import { ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { useSession } from "@/components/session-provider";
import { useSelectedMembershipRole } from "@/lib/membership-role";

import { seasonErrorKey, seasonMoney, seasonRange, statusTone } from "./season-ui";

/**
 * Seasons in Box › Συνδρομή (ADR-167): one line in the membership card,
 * shown only while the gym has a season open or the member is in one. It
 * opens one sheet: the list, and a season's detail with «Ζήτα θέση» /
 * «Απόσυρση» and where the request stands. `/box?season=ID` (the season
 * notifications) opens that season straight away.
 */
export function SeasonsEntry() {
  const t = useTranslations("Seasons");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const { membership } = useSelectedMembershipRole();
  const organizationId = membership?.organization.id ?? null;
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const linked = searchParams.get("season");
  const [open, setOpen] = useState(false);

  const seasons = useQuery({
    queryKey: [...MY_SEASONS_KEY, organizationId],
    enabled: Boolean(token && organizationId),
    queryFn: () => fetchMySeasons(token),
  });
  const list = Array.isArray(seasons.data) ? seasons.data.filter((season) => season?.id) : [];
  if (list.length === 0) return null;

  const mine = list.find((season) => season.mine?.status === "active" || season.mine?.status === "requested" || season.mine?.status === "waitlisted");
  const sheetOpen = open || Boolean(linked);

  function close() {
    setOpen(false);
    if (linked) {
      const params = new URLSearchParams(searchParams.toString());
      params.delete("season");
      const query = params.toString();
      router.replace(query ? `${pathname}?${query}` : pathname, { scroll: false });
    }
  }

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="flex min-h-11 w-full items-center justify-between gap-3 rounded-2xl px-4 text-left text-sm font-bold"
        style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
      >
        <span className="truncate">{mine ? mine.title : t("entry", { count: list.length })}</span>
        {mine?.mine ? (
          <span className="shrink-0 text-xs font-semibold" style={{ color: statusTone(mine.mine.status) }}>
            {t(`mine_${mine.mine.status}`)}
          </span>
        ) : (
          <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
        )}
      </button>
      {sheetOpen ? <SeasonsSheet seasons={list} token={token} initialId={linked} onClose={close} /> : null}
    </>
  );
}

function SeasonsSheet({
  seasons,
  token,
  initialId,
  onClose,
}: {
  seasons: MemberSeason[];
  token: string;
  initialId: string | null;
  onClose: () => void;
}) {
  const t = useTranslations("Seasons");
  const locale = useLocale();
  const [selectedId, setSelectedId] = useState<string | null>(
    initialId && seasons.some((season) => season.id === initialId) ? initialId : seasons.length === 1 ? seasons[0].id : null,
  );
  const selected = seasons.find((season) => season.id === selectedId) ?? null;

  if (!selected) {
    return (
      <Sheet labelId="seasons-sheet" title={t("title")} eyebrow={t("eyebrow")} onClose={onClose}>
        <ul className="flex flex-col gap-2 pb-2">
          {seasons.map((season) => (
            <li key={season.id}>
              <button
                type="button"
                onClick={() => setSelectedId(season.id)}
                className="flex w-full flex-col gap-1 rounded-2xl px-4 py-3 text-left"
                style={{ background: "var(--panel-raised)", border: "1px solid var(--border)" }}
              >
                <span className="flex items-center justify-between gap-2">
                  <span className="truncate text-sm font-bold" style={{ color: "var(--text)" }}>{season.title}</span>
                  {season.mine ? (
                    <span className="shrink-0 text-xs font-semibold" style={{ color: statusTone(season.mine.status) }}>
                      {t(`mine_${season.mine.status}`)}
                    </span>
                  ) : null}
                </span>
                <span className="text-xs" style={{ color: "var(--text-soft)" }}>
                  {seasonRange(locale, season.starts_on, season.ends_on)}
                  {" · "}
                  {seasonMoney(locale, season.price_cents, season.currency)}
                </span>
              </button>
            </li>
          ))}
        </ul>
      </Sheet>
    );
  }

  return <SeasonDetail season={selected} token={token} onBack={seasons.length > 1 ? () => setSelectedId(null) : null} onClose={onClose} />;
}

function SeasonDetail({
  season,
  token,
  onBack,
  onClose,
}: {
  season: MemberSeason;
  token: string;
  onBack: (() => void) | null;
  onClose: () => void;
}) {
  const t = useTranslations("Seasons");
  const locale = useLocale();
  const queryClient = useQueryClient();
  const action = memberSeasonAction(season);
  const placesLeft = typeof season.places_left === "number" ? season.places_left : null;
  const coaches = (season.coaches ?? []).map((coach) => coach.nickname).filter(Boolean).join(", ");

  const act = useMutation({
    mutationFn: () => (action === "cancel" ? cancelSeasonRequest(token, season.id) : requestSeasonPlace(token, season.id)),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: MY_SEASONS_KEY }),
  });

  const footer = (
    <>
      {onBack ? <SheetButton onClick={onBack}>{t("back")}</SheetButton> : <SheetButton onClick={onClose}>{t("close")}</SheetButton>}
      {action ? (
        <SheetButton primary={action === "request"} disabled={act.isPending} onClick={() => act.mutate()}>
          {action === "cancel" ? t("withdraw") : placesLeft === 0 ? t("joinWaitlist") : t("request")}
        </SheetButton>
      ) : null}
    </>
  );

  return (
    <Sheet labelId="season-detail" title={season.title} eyebrow={t("eyebrow")} onClose={onClose} footer={footer}>
      <div className="flex flex-col gap-4 pb-2">
        <dl className="grid grid-cols-2 gap-3 text-sm">
          <Fact label={t("dates")} value={seasonRange(locale, season.starts_on, season.ends_on)} />
          <Fact label={t("weeksLabel")} value={t("weeks", { count: season.weeks ?? 0 })} />
          <Fact label={t("price")} value={seasonMoney(locale, season.price_cents, season.currency)} />
          <Fact
            label={t("places")}
            value={placesLeft === null ? "" : placesLeft > 0 ? t("placesLeft", { count: placesLeft }) : t("placesFull")}
          />
          {coaches ? <Fact label={t("coaches")} value={coaches} /> : null}
          {season.workout_count ? <Fact label={t("programme")} value={t("workouts", { count: season.workout_count })} /> : null}
        </dl>
        {season.description ? (
          <p className="whitespace-pre-line text-sm" style={{ color: "var(--text-soft)" }}>{season.description}</p>
        ) : null}
        {season.mine ? (
          <div
            className="rounded-2xl px-4 py-3 text-sm"
            style={{ background: "var(--panel-raised)", border: `1px solid ${statusTone(season.mine.status)}` }}
          >
            <p className="font-bold" style={{ color: statusTone(season.mine.status) }}>{t(`mine_${season.mine.status}`)}</p>
            <p className="mt-1" style={{ color: "var(--text-soft)" }}>{t(`mineHint_${season.mine.status}`)}</p>
            {season.mine.status === "declined" && season.mine.decline_reason ? (
              <p className="mt-1 italic" style={{ color: "var(--text-soft)" }}>{season.mine.decline_reason}</p>
            ) : null}
          </div>
        ) : action === "request" ? (
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t("requestHint")}</p>
        ) : null}
        <ErrorLine message={act.error ? t(seasonErrorKey(act.error)) : null} />
      </div>
    </Sheet>
  );
}

function Fact({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-xs font-semibold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{label}</dt>
      <dd className="mt-0.5 font-semibold" style={{ color: "var(--text)" }}>{value || "—"}</dd>
    </div>
  );
}
