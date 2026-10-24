"use client";

import Link from "next/link";
import { useRef, useState, type PointerEvent, type ReactNode } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  PARTNER_MATCHES_KEY,
  partnersClubKey,
  swipePartner,
  undoPartnerSwipe,
  type PartnerCard,
  type PartnerMatch,
  type PartnerOptions,
  type PartnersClubOverview,
  type SwipeDirection,
} from "@/api/partners";
import { ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { ListFilters } from "@/components/filters/ListFilters";
import { useListFilter } from "@/components/filters/use-remembered-filter";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useUiTranslations } from "@/i18n/ui";

import { PartnerTag } from "./PartnerBits";
import { partnerErrorMessage } from "./errors";
import { PARTNER_DECK_SHAPE, activeFilters, partnerFilters, withoutCard, type PartnerDeckFilter } from "./partners-model";
import { usePartnerDeck, usePartnersToken } from "./use-partners";

const DRAG_THRESHOLD = 90;
const LOW_SWIPES = 20;

type LastSwipe = { card: PartnerCard; direction: SwipeDirection };

/**
 * The deck (ADR-169 §3): one person at a time, best fit first, with what you
 * both share on top. ✕ is «Όχι τώρα», ✓ is «Να προπονηθούμε»; a drag does the
 * same. The last swipe can be taken back unless it made a match. A match
 * opens «Βρήκατε partner» with the way into the conversation. Its filters
 * are the chip row + «Φίλτρα (n)» of every list, remembered per club.
 */
export function PartnerDeck({
  clubId,
  options,
  swipesRemaining,
  distance,
}: {
  clubId: string;
  options: PartnerOptions;
  swipesRemaining: number;
  /** ADR-197: «available» in an open club when you show in Γύρω μου with an area. */
  distance: PartnersClubOverview["distance"];
}) {
  const { filter, setFilter, empty } = useListFilter("partners", PARTNER_DECK_SHAPE, clubId);
  const t = useTranslations("Partners");
  if (!filter) return <p className="text-sm" role="status" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  return (
    <Deck
      clubId={clubId}
      options={options}
      swipesRemaining={swipesRemaining}
      distance={distance}
      filter={filter}
      onFilter={setFilter}
      empty={empty}
    />
  );
}

function Deck({
  clubId,
  options,
  swipesRemaining,
  distance,
  filter,
  onFilter,
  empty,
}: {
  clubId: string;
  options: PartnerOptions;
  swipesRemaining: number;
  distance: PartnersClubOverview["distance"];
  filter: PartnerDeckFilter;
  onFilter: (next: PartnerDeckFilter) => void;
  empty: PartnerDeckFilter;
}) {
  const t = useTranslations("Partners");
  const tags = useTranslations("BoxTags");
  const tUi = useUiTranslations();
  const token = usePartnersToken();
  const queryClient = useQueryClient();
  const filters = partnerFilters(filter, options, distance === "available");
  const [gone, setGone] = useState<string[]>([]);
  const [last, setLast] = useState<LastSwipe | null>(null);
  const [match, setMatch] = useState<PartnerMatch | null>(null);
  const [remaining, setRemaining] = useState<number | null>(null);
  const deck = usePartnerDeck(clubId, filters, true);
  const cards = (deck.data?.cards ?? []).filter((card) => !gone.includes(card.person.id));
  const card = cards[0] ?? null;
  const left = remaining ?? deck.data?.swipes_remaining ?? swipesRemaining;

  const swipe = useMutation({
    mutationFn: ({ target, direction }: { target: PartnerCard; direction: SwipeDirection }) =>
      swipePartner(token!, clubId, target.person.id, direction),
    onMutate: ({ target }) => setGone((ids) => [...ids, target.person.id]),
    onSuccess: (result, { target, direction }) => {
      setRemaining(result.swipes_remaining);
      if (result.match) {
        setLast(null);
        setMatch(result.match);
        void queryClient.invalidateQueries({ queryKey: PARTNER_MATCHES_KEY });
      } else {
        setLast({ card: target, direction });
      }
      if (withoutCard(cards, target.person.id).length === 0) void deck.refetch();
    },
    onError: (_error, { target }) => setGone((ids) => ids.filter((id) => id !== target.person.id)),
  });

  const undo = useMutation({
    mutationFn: (previous: LastSwipe) => undoPartnerSwipe(token!, clubId, previous.card.person.id),
    onSuccess: (_result, previous) => {
      setGone((ids) => ids.filter((id) => id !== previous.card.person.id));
      setLast(null);
      void queryClient.invalidateQueries({ queryKey: partnersClubKey(clubId), exact: true });
    },
  });

  const act = (direction: SwipeDirection) => {
    if (card && !swipe.isPending) swipe.mutate({ target: card, direction });
  };
  const changeFilters = (next: PartnerDeckFilter) => {
    onFilter(next);
    setGone([]);
    setLast(null);
  };
  const count = activeFilters(filters);
  const choices = <T extends string | number>(values: readonly T[], label: (value: T) => string) =>
    values.map((value) => ({ value: String(value), label: label(value) }));

  return (
    <div className="flex flex-col gap-3" data-testid="partner-deck">
      <div data-testid="partner-filters">
        <ListFilters
          shape={PARTNER_DECK_SHAPE}
          fields={[
            { key: "time", label: t("timesLabelShort"), options: choices(options.times, (time) => t(`time_${time}`)) },
            { key: "level", label: t("levelLabel"), options: choices(options.levels, (level) => t(`level_${level}`)) },
            { key: "goal", label: t("goalLabelShort"), options: choices(options.goals, (goal) => t(`goal_${goal}`)), chip: false },
            { key: "discipline", label: t("disciplineLabel"), options: choices(options.disciplines, (key) => tags(`discipline.${key}`)), chip: false },
            ...(distance === "available"
              ? [{ key: "within" as const, label: t("distanceLabel"), options: choices(options.distances_km, (km) => t("withinKm", { km })) }]
              : []),
          ]}
          filter={filter}
          onChange={changeFilters}
          title={t("filters")}
        />
      </div>
      {distance === "needs_area" ? (
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("distanceNeedsArea")}</p>
      ) : null}
      {left <= LOW_SWIPES ? (
        <span className="text-xs" style={{ color: "var(--dim)" }}>{t("swipesLeft", { count: left })}</span>
      ) : null}

      {deck.isPending ? (
        <p className="text-sm" role="status" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : left <= 0 ? (
        <Empty text={t("limitReached")} />
      ) : card ? (
        <SwipeCard key={card.person.id} card={card} onSwipe={act} busy={swipe.isPending} />
      ) : (
        <Empty text={count > 0 ? t("deckEmptyFiltered") : t("deckEmpty")}>
          {count > 0 ? (
            <button type="button" onClick={() => changeFilters(empty)} className="min-h-11 text-sm font-semibold" style={{ color: "var(--primary)" }}>
              {t("clearFilters")}
            </button>
          ) : null}
        </Empty>
      )}

      {last ? (
        <button
          type="button"
          onClick={() => undo.mutate(last)}
          disabled={undo.isPending}
          className="min-h-11 self-center text-sm font-semibold disabled:opacity-50"
          style={{ color: "var(--primary)" }}
          data-testid="partner-undo"
        >
          {t("undo", { name: last.card.person.nickname ?? t("someone") })}
        </button>
      ) : null}

      <ErrorLine message={partnerErrorMessage(swipe.error ?? undo.error, t, tUi)} />
      {match ? <MatchSheet match={match} onClose={() => setMatch(null)} /> : null}
    </div>
  );
}

function SwipeCard({ card, onSwipe, busy }: { card: PartnerCard; onSwipe: (direction: SwipeDirection) => void; busy: boolean }) {
  const t = useTranslations("Partners");
  const tags = useTranslations("BoxTags");
  const name = card.person.nickname ?? t("someone");
  const start = useRef<number | null>(null);
  const [dx, setDx] = useState(0);
  const shared = [
    ...(card.shared.same_level ? [t(`level_${card.level}`)] : []),
    ...card.shared.times.map((time) => t(`time_${time}`)),
    ...card.shared.goals.map((goal) => t(`goal_${goal}`)),
    ...(card.shared.disciplines ?? []).map((key) => tags(`discipline.${key}`)),
  ];

  const down = (event: PointerEvent<HTMLElement>) => {
    if (event.pointerType === "mouse") return;
    start.current = event.clientX;
  };
  const move = (event: PointerEvent<HTMLElement>) => {
    if (start.current !== null) setDx(event.clientX - start.current);
  };
  const up = () => {
    if (start.current === null) return;
    start.current = null;
    if (dx > DRAG_THRESHOLD) onSwipe("like");
    else if (dx < -DRAG_THRESHOLD) onSwipe("pass");
    setDx(0);
  };

  return (
    <article
      aria-label={name}
      onPointerDown={down}
      onPointerMove={move}
      onPointerUp={up}
      onPointerCancel={() => {
        start.current = null;
        setDx(0);
      }}
      className="flex touch-pan-y flex-col gap-3 rounded-3xl p-4"
      style={{
        background: "var(--panel-raised)",
        border: "1px solid var(--border)",
        transform: dx ? `translateX(${dx}px) rotate(${dx / 30}deg)` : undefined,
      }}
      data-testid="partner-card"
    >
      <div className="flex items-center gap-3">
        <PersonAvatar name={name} url={card.person.avatar_url} size={56} />
        <div className="min-w-0">
          <h3 className="truncate text-lg font-extrabold" style={{ color: "var(--text)" }}>{name}</h3>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t(`level_${card.level}`)}</p>
        </div>
      </div>
      {shared.length > 0 ? (
        <p className="text-sm font-semibold" style={{ color: "var(--primary-strong, var(--primary))" }}>
          {t("sharedLine", { items: shared.join(" · ") })}
        </p>
      ) : null}
      <div className="flex flex-wrap gap-1.5">
        {card.times.map((time) => (
          <PartnerTag key={time} strong={card.shared.times.includes(time)}>{t(`time_${time}`)}</PartnerTag>
        ))}
        {card.goals.map((goal) => (
          <PartnerTag key={goal} strong={card.shared.goals.includes(goal)}>{t(`goal_${goal}`)}</PartnerTag>
        ))}
        {(card.disciplines ?? []).map((key) => (
          <PartnerTag key={key} strong={(card.shared.disciplines ?? []).includes(key)}>{tags(`discipline.${key}`)}</PartnerTag>
        ))}
      </div>
      {card.about ? <p className="text-sm" style={{ color: "var(--text)" }}>{card.about}</p> : null}
      <div className="flex gap-3 pt-1">
        <button
          type="button"
          onClick={() => onSwipe("pass")}
          disabled={busy}
          aria-label={t("passLabel", { name })}
          className="min-h-12 flex-1 rounded-2xl text-lg font-bold disabled:opacity-50"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
        >
          ✕
        </button>
        <button
          type="button"
          onClick={() => onSwipe("like")}
          disabled={busy}
          aria-label={t("likeLabel", { name })}
          className="min-h-12 flex-1 rounded-2xl text-lg font-bold disabled:opacity-50"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          ✓
        </button>
      </div>
    </article>
  );
}

function Empty({ text, children }: { text: string; children?: ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-1 rounded-3xl px-4 py-6 text-center" style={{ background: "var(--panel-muted)" }}>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{text}</p>
      {children}
    </div>
  );
}

/** «Βρήκατε partner»: you both said yes. */
function MatchSheet({ match, onClose }: { match: PartnerMatch; onClose: () => void }) {
  const t = useTranslations("Partners");
  const name = match.person.nickname ?? t("someone");
  return (
    <Sheet
      labelId={`partner-match-${match.id}`}
      title={t("matchTitle")}
      onClose={onClose}
      footer={
        <>
          <SheetButton onClick={onClose}>{t("later")}</SheetButton>
          <Link
            href={`/partners/${encodeURIComponent(match.id)}`}
            className="flex min-h-11 flex-1 items-center justify-center rounded-2xl px-4 text-sm font-bold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {t("sayHi")}
          </Link>
        </>
      }
    >
      <div className="flex flex-col items-center gap-3 py-2 text-center" data-testid="partner-match">
        <PersonAvatar name={name} url={match.person.avatar_url} size={72} />
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("matchBody", { name })}</p>
      </div>
    </Sheet>
  );
}
