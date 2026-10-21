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
  type PartnerFilters,
  type PartnerMatch,
  type PartnerOptions,
  type SwipeDirection,
} from "@/api/partners";
import { ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useUiTranslations } from "@/i18n/ui";

import { PartnerChip, PartnerTag } from "./PartnerBits";
import { partnerErrorMessage } from "./errors";
import { activeFilters, withoutCard } from "./partners-model";
import { usePartnerDeck, usePartnersToken } from "./use-partners";

const DRAG_THRESHOLD = 90;
const LOW_SWIPES = 20;

type LastSwipe = { card: PartnerCard; direction: SwipeDirection };

/**
 * The deck (ADR-169 §3): one person at a time, best fit first, with what you
 * both share on top. ✕ is «Όχι τώρα», ✓ is «Να προπονηθούμε»; a drag does the
 * same. The last swipe can be taken back unless it made a match. A match
 * opens «Βρήκατε partner» with the way into the conversation.
 */
export function PartnerDeck({ clubId, options, swipesRemaining }: { clubId: string; options: PartnerOptions; swipesRemaining: number }) {
  const t = useTranslations("Partners");
  const tUi = useUiTranslations();
  const token = usePartnersToken();
  const queryClient = useQueryClient();
  const [filters, setFilters] = useState<PartnerFilters>({});
  const [showFilters, setShowFilters] = useState(false);
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
  const changeFilters = (next: PartnerFilters) => {
    setFilters(next);
    setGone([]);
    setLast(null);
  };
  const count = activeFilters(filters);

  return (
    <div className="flex flex-col gap-3" data-testid="partner-deck">
      <div className="flex items-center justify-between gap-2">
        <button
          type="button"
          aria-expanded={showFilters}
          onClick={() => setShowFilters((open) => !open)}
          className="min-h-10 rounded-full px-3.5 text-sm font-semibold"
          style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {count > 0 ? t("filtersCount", { count }) : t("filters")}
        </button>
        {left <= LOW_SWIPES ? (
          <span className="text-xs" style={{ color: "var(--dim)" }}>{t("swipesLeft", { count: left })}</span>
        ) : null}
      </div>

      {showFilters ? <Filters options={options} filters={filters} onChange={changeFilters} /> : null}

      {deck.isPending ? (
        <p className="text-sm" role="status" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : left <= 0 ? (
        <Empty text={t("limitReached")} />
      ) : card ? (
        <SwipeCard key={card.person.id} card={card} onSwipe={act} busy={swipe.isPending} />
      ) : (
        <Empty text={count > 0 ? t("deckEmptyFiltered") : t("deckEmpty")}>
          {count > 0 ? (
            <button type="button" onClick={() => changeFilters({})} className="min-h-11 text-sm font-semibold" style={{ color: "var(--primary)" }}>
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
  const name = card.person.nickname ?? t("someone");
  const start = useRef<number | null>(null);
  const [dx, setDx] = useState(0);
  const shared = [
    ...(card.shared.same_level ? [t(`level_${card.level}`)] : []),
    ...card.shared.times.map((time) => t(`time_${time}`)),
    ...card.shared.goals.map((goal) => t(`goal_${goal}`)),
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

function Filters({ options, filters, onChange }: { options: PartnerOptions; filters: PartnerFilters; onChange: (next: PartnerFilters) => void }) {
  const t = useTranslations("Partners");
  const row = <K extends keyof PartnerFilters>(field: K, label: string, values: readonly NonNullable<PartnerFilters[K]>[], prefix: string) => (
    <div className="flex flex-col gap-1.5">
      <p className="text-xs font-semibold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>{label}</p>
      <div className="flex flex-wrap gap-1.5">
        {values.map((value) => (
          <PartnerChip
            key={value}
            pressed={filters[field] === value}
            onToggle={() => onChange({ ...filters, [field]: filters[field] === value ? null : value })}
          >
            {t([prefix, value].join("_"))}
          </PartnerChip>
        ))}
      </div>
    </div>
  );
  return (
    <div className="flex flex-col gap-3 rounded-2xl p-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }} data-testid="partner-filters">
      {row("time", t("timesLabelShort"), options.times, "time")}
      {row("level", t("levelLabel"), options.levels, "level")}
      {row("goal", t("goalLabelShort"), options.goals, "goal")}
    </div>
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
