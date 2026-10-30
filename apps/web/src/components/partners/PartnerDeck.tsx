"use client";

import Link from "next/link";
import { useEffect, useId, useRef, useState, type PointerEvent, type ReactNode } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  PARTNERS_OVERVIEW_KEY,
  PARTNER_MATCHES_KEY,
  swipePartner,
  undoPartnerSwipe,
  type PartnerCard,
  type PartnerMatch,
  type PartnersOverview,
  type SwipeDirection,
} from "@/api/partners";
import { usePrefersReducedMotion } from "@/components/anatomy/use-anatomy-environment";
import { ErrorLine, Sheet, SheetButton } from "@/components/community/Sheet";
import { ChoiceChips, FilterPage, FilterSection } from "@/components/filters/FilterPage";
import { useListFilter } from "@/components/filters/use-remembered-filter";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { useUiTranslations } from "@/i18n/ui";

import { PartnerBadgePill, PartnerIcon, PartnerTag } from "./PartnerBits";
import { partnerErrorMessage } from "./errors";
import {
  PARTNERS_AREA_HREF,
  PARTNER_DECK_SHAPE,
  activeFilters,
  badgeText,
  partnerFilters,
  sharedParts,
  widerDistance,
  withoutCard,
  type PartnerDeckFilter,
  type SharedPart,
} from "./partners-model";
import { FLY_MS, dragTransform, flyTransform, keyDecision, stampOpacity, swipeDecision } from "./swipe-gesture";
import { usePartnerDeck, usePartnersToken } from "./use-partners";

type LastSwipe = { card: PartnerCard; direction: SwipeDirection };

const ALL = "__all";
/** Where the arrow keys keep their usual meaning: typing, or inside a sheet. */
const NO_SWIPE_KEYS_WITHIN = ['[role="dialog"]', "input", "textarea", '[contenteditable="true"]'].join(", ");

/**
 * The deck (ADR-280, mockup decision 3 C): one person at a time on a card
 * that fills the screen, the next one waiting behind it. Drag right for
 * «ναι», left for «όχι», or use the floating ✕/✓ or the arrow keys. The last
 * swipe can be taken back unless it made a match; a match opens «Βρήκατε
 * συναθλητή» with the way into the conversation. «Φίλτρα» narrows by time,
 * level, goal, discipline and distance, remembered across devices.
 */
export function PartnerDeck({ overview }: { overview: PartnersOverview }) {
  const { filter, setFilter, empty } = useListFilter("partners", PARTNER_DECK_SHAPE);
  const t = useTranslations("Partners");
  if (!filter) return <p className="text-sm" role="status" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  return <Deck overview={overview} filter={filter} onFilter={setFilter} empty={empty} />;
}

function Deck({
  overview,
  filter,
  onFilter,
  empty,
}: {
  overview: PartnersOverview;
  filter: PartnerDeckFilter;
  onFilter: (next: PartnerDeckFilter) => void;
  empty: PartnerDeckFilter;
}) {
  const t = useTranslations("Partners");
  const tUi = useUiTranslations();
  const token = usePartnersToken();
  const queryClient = useQueryClient();
  const reducedMotion = usePrefersReducedMotion();
  const { options } = overview;
  const distance = overview.distance === "available";
  const filters = partnerFilters(filter, options);
  const [gone, setGone] = useState<string[]>([]);
  const [last, setLast] = useState<LastSwipe | null>(null);
  const [match, setMatch] = useState<PartnerMatch | null>(null);
  const [remaining, setRemaining] = useState<number | null>(null);
  const [liked, setLiked] = useState(0);
  const [flying, setFlying] = useState<SwipeDirection | null>(null);
  const [filtersOpen, setFiltersOpen] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const deck = usePartnerDeck(filters, true);
  const cards = (deck.data?.cards ?? []).filter((card) => !gone.includes(card.person.id));
  const card = cards[0] ?? null;
  const next = cards[1] ?? null;
  const left = remaining ?? deck.data?.swipes_remaining ?? overview.swipes_remaining;
  const km = deck.data?.within_km ?? filters.within_km ?? options.default_within_km;
  const count = activeFilters(filters);

  useEffect(() => () => {
    if (timer.current) clearTimeout(timer.current);
  }, []);

  const swipe = useMutation({
    mutationFn: ({ target, direction }: { target: PartnerCard; direction: SwipeDirection }) => swipePartner(token!, target.person.id, direction),
    onSuccess: (result, { target, direction }) => {
      setRemaining(result.swipes_remaining);
      if (direction === "like") setLiked((value) => value + 1);
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
    mutationFn: (previous: LastSwipe) => undoPartnerSwipe(token!, previous.card.person.id),
    onSuccess: (_result, previous) => {
      setGone((ids) => ids.filter((id) => id !== previous.card.person.id));
      if (previous.direction === "like") setLiked((value) => Math.max(0, value - 1));
      setRemaining((value) => (value === null ? null : value + 1));
      setLast(null);
      void queryClient.invalidateQueries({ queryKey: PARTNERS_OVERVIEW_KEY, exact: true });
    },
  });

  const busy = flying !== null;
  /** Flies the top card out, then records the swipe; false when nothing can be swiped now. */
  const decide = (direction: SwipeDirection) => {
    if (!card || busy || left <= 0) return false;
    const target = card;
    setFlying(direction);
    timer.current = setTimeout(() => {
      setGone((ids) => [...ids, target.person.id]);
      setFlying(null);
      swipe.mutate({ target, direction });
    }, reducedMotion ? 0 : FLY_MS);
    return true;
  };
  const decideRef = useRef(decide);
  useEffect(() => {
    decideRef.current = decide;
  });

  // ← and → swipe, unless typing or inside a sheet.
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      const direction = keyDecision(event.key);
      if (!direction || event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey) return;
      const target = event.target as HTMLElement | null;
      if (target?.closest?.(NO_SWIPE_KEYS_WITHIN)) return;
      event.preventDefault();
      decideRef.current(direction);
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, []);

  const changeFilters = (nextFilter: PartnerDeckFilter) => {
    onFilter(nextFilter);
    setGone([]);
    setLast(null);
  };
  const wider = widerDistance(km, options);

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-2" data-testid="partner-deck">
      <div className="flex flex-wrap items-center gap-2">
        <button
          type="button"
          onClick={() => setFiltersOpen(true)}
          className="inline-flex min-h-10 items-center gap-1.5 rounded-full px-3.5 text-sm font-bold"
          style={{ background: "var(--panel-raised)", border: `1px solid ${count > 0 ? "var(--primary)" : "var(--border)"}`, color: "var(--text)" }}
          data-testid="partner-filters"
        >
          <PartnerIcon name="filters" size={18} />
          {distance ? <span>{t("withinKmShort", { km })} · </span> : null}
          {count > 0 ? t("filtersCount", { count }) : t("filters")}
        </button>
        <span className="text-xs" style={{ color: "var(--dim)" }} data-testid="partner-swipes-left">
          {t("swipesLeft", { count: left })}
        </span>
        {last ? (
          <button
            type="button"
            onClick={() => undo.mutate(last)}
            disabled={undo.isPending}
            className="ms-auto inline-flex min-h-10 items-center gap-1.5 rounded-full px-3 text-sm font-semibold disabled:opacity-50"
            style={{ color: "var(--primary)" }}
            data-testid="partner-undo"
          >
            <PartnerIcon name="undo" size={18} className="rtl:-scale-x-100" />
            {t("undo", { name: last.card.person.nickname ?? t("someone") })}
          </button>
        ) : null}
      </div>
      {!distance ? (
        <p className="text-xs" style={{ color: "var(--text-soft)" }} data-testid="partner-needs-area">
          {t("distanceNeedsArea")}{" "}
          <Link href={PARTNERS_AREA_HREF} className="font-semibold underline" style={{ color: "var(--primary)" }}>
            {t("distanceSetArea")}
          </Link>
        </p>
      ) : null}

      <div className="relative min-h-0 flex-1">
        {deck.isPending ? (
          <p className="text-sm" role="status" style={{ color: "var(--dim)" }}>{t("loading")}</p>
        ) : deck.isError ? (
          <ErrorLine message={partnerErrorMessage(deck.error, t, tUi)} />
        ) : left <= 0 ? (
          <Empty title={t("doneTitle")} text={t("limitReached")} />
        ) : card ? (
          <>
            {next ? (
              <div aria-hidden="true" inert className="absolute inset-0 scale-[0.96] opacity-80">
                <CardFace card={next} km={distance ? km : null} />
              </div>
            ) : null}
            <SwipeCard key={card.person.id} card={card} km={distance ? km : null} flying={flying} reducedMotion={reducedMotion} onDecide={decide} />
            <div dir="ltr" className="pointer-events-none absolute inset-x-0 bottom-4 flex justify-center gap-8">
              <RoundButton
                label={t("passLabel", { name: card.person.nickname ?? t("someone") })}
                onClick={() => decide("pass")}
                disabled={busy}
                tone="pass"
              />
              <RoundButton
                label={t("likeLabel", { name: card.person.nickname ?? t("someone") })}
                onClick={() => decide("like")}
                disabled={busy}
                tone="like"
              />
            </div>
          </>
        ) : count > 0 ? (
          <Empty title={t("doneTitle")} text={t("deckEmptyFiltered")}>
            <TextButton onClick={() => changeFilters(empty)}>{t("clearFilters")}</TextButton>
          </Empty>
        ) : (
          <Empty title={t("doneTitle")} text={liked > 0 ? t("doneLiked") : distance && wider ? t("doneWider") : t("deckEmpty")}>
            {distance && wider ? (
              <TextButton onClick={() => changeFilters({ ...filter, within: [String(wider)] })}>{t("widenTo", { km: wider })}</TextButton>
            ) : null}
          </Empty>
        )}
      </div>

      <ErrorLine message={partnerErrorMessage(swipe.error ?? undo.error, t, tUi)} />
      {filtersOpen ? (
        <DeckFilters overview={overview} filter={filter} onChange={changeFilters} onClear={() => changeFilters(empty)} onClose={() => setFiltersOpen(false)} />
      ) : null}
      {match ? <MatchSheet match={match} onClose={() => setMatch(null)} /> : null}
    </div>
  );
}

/** The card on top: it follows the finger (or mouse) and decides past the threshold. */
function SwipeCard({
  card,
  km,
  flying,
  reducedMotion,
  onDecide,
}: {
  card: PartnerCard;
  km: number | null;
  flying: SwipeDirection | null;
  reducedMotion: boolean;
  onDecide: (direction: SwipeDirection) => boolean;
}) {
  const t = useTranslations("Partners");
  const hintId = useId();
  const start = useRef<number | null>(null);
  const [dx, setDx] = useState(0);
  const [dragging, setDragging] = useState(false);
  const name = card.person.nickname ?? t("someone");

  const down = (event: PointerEvent<HTMLElement>) => {
    if (flying || (event.pointerType === "mouse" && event.button !== 0)) return;
    start.current = event.clientX;
    setDragging(true);
    event.currentTarget.setPointerCapture?.(event.pointerId);
  };
  const move = (event: PointerEvent<HTMLElement>) => {
    if (start.current !== null) setDx(event.clientX - start.current);
  };
  const up = () => {
    if (start.current === null) return;
    start.current = null;
    setDragging(false);
    const decision = swipeDecision(dx);
    if (!decision || !onDecide(decision)) setDx(0);
  };
  const cancel = () => {
    start.current = null;
    setDragging(false);
    setDx(0);
  };

  const shown = flying ? (flying === "like" ? 1 : -1) * 200 : dx;
  const stamps = stampOpacity(shown);
  return (
    <article
      aria-label={name}
      aria-describedby={hintId}
      onPointerDown={down}
      onPointerMove={move}
      onPointerUp={up}
      onPointerCancel={cancel}
      className="absolute inset-0 cursor-grab select-none touch-pan-y active:cursor-grabbing"
      style={{
        transform: flying ? flyTransform(flying, reducedMotion) : dragTransform(dx, reducedMotion),
        transition: dragging || reducedMotion ? "none" : `transform ${FLY_MS}ms ease`,
      }}
      data-testid="partner-card"
    >
      <span id={hintId} className="sr-only">{t("swipeHint")}</span>
      <CardFace card={card} km={km} />
      <Stamp side="like" opacity={stamps.like}>{t("stampYes")}</Stamp>
      <Stamp side="pass" opacity={stamps.pass}>{t("stampNo")}</Stamp>
    </article>
  );
}

/** What a card shows (ADR-280): avatar, name, badge, level, times, goals, disciplines, their line, «Κοινά» and the distance. */
function CardFace({ card, km }: { card: PartnerCard; km: number | null }) {
  const t = useTranslations("Partners");
  const tags = useTranslations("BoxTags");
  const name = card.person.nickname ?? t("someone");
  const badge = badgeText(card.badge);
  const shared = sharedParts(card);
  const label = (part: SharedPart) =>
    part.kind === "discipline" ? tags(`discipline.${part.value}`) : t(`${part.kind}_${part.value}`);
  return (
    <div
      className="flex h-full flex-col overflow-hidden rounded-3xl"
      style={{ background: "var(--panel)", border: "1px solid var(--border)", boxShadow: "0 8px 28px color-mix(in srgb, var(--text) 12%, transparent)" }}
    >
      <div
        className="grid shrink-0 basis-[38%] place-items-center"
        style={{ background: "linear-gradient(160deg, color-mix(in srgb, var(--primary) 18%, var(--panel)), var(--panel))" }}
      >
        <PersonAvatar name={name} url={card.person.avatar_url} size={120} />
      </div>
      <div className="flex min-h-0 flex-1 flex-col gap-2.5 overflow-y-auto px-4 pb-28 pt-4">
        <h2 className="truncate text-2xl font-extrabold" style={{ color: "var(--text)" }}>{name}</h2>
        {badge ? <PartnerBadgePill>{t(badge.key, { box: badge.box ?? "" })}</PartnerBadgePill> : null}
        <div className="flex flex-wrap gap-1.5">
          <PartnerTag strong={card.shared.same_level}>{t(`level_${card.level}`)}</PartnerTag>
          {card.times.map((time) => (
            <PartnerTag key={time} strong={card.shared.times.includes(time)}>{t(`time_${time}`)}</PartnerTag>
          ))}
          {card.goals.map((goal) => (
            <PartnerTag key={goal} strong={card.shared.goals.includes(goal)}>{t(`goal_${goal}`)}</PartnerTag>
          ))}
          {card.disciplines.map((key) => (
            <PartnerTag key={key} strong={card.shared.disciplines.includes(key)}>{tags(`discipline.${key}`)}</PartnerTag>
          ))}
        </div>
        {card.about ? (
          <p className="text-base" style={{ color: "var(--text)" }} data-testid="partner-about">
            {t("aboutQuoted", { about: card.about })}
          </p>
        ) : null}
        {shared.length > 0 ? (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>
            <span className="font-bold" style={{ color: "var(--text)" }}>{t("sharedLabel")}</span> {shared.map(label).join(" · ")}
          </p>
        ) : null}
        {km !== null ? (
          <p className="inline-flex items-center gap-1 text-sm" style={{ color: "var(--text-soft)" }}>
            <PartnerIcon name="pin" size={16} />
            {t("withinKm", { km })}
          </p>
        ) : null}
      </div>
    </div>
  );
}

function Stamp({ side, opacity, children }: { side: SwipeDirection; opacity: number; children: string }) {
  const like = side === "like";
  return (
    <span
      aria-hidden="true"
      className={["pointer-events-none absolute top-8 rounded-lg border-[3px] px-3 py-1 text-xl font-extrabold tracking-wider", like ? "left-5 -rotate-12" : "right-5 rotate-12"].join(" ")}
      style={{ opacity, color: like ? "var(--success)" : "var(--danger)", borderColor: like ? "var(--success)" : "var(--danger)", background: "var(--panel)" }}
    >
      {children}
    </span>
  );
}

function RoundButton({ label, onClick, disabled, tone }: { label: string; onClick: () => void; disabled: boolean; tone: SwipeDirection }) {
  const like = tone === "like";
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-label={label}
      className="pointer-events-auto grid h-16 w-16 place-items-center rounded-full disabled:opacity-60"
      style={{
        background: like ? "var(--primary)" : "var(--panel)",
        color: like ? "var(--primary-contrast)" : "var(--danger)",
        border: like ? "none" : "1px solid var(--border)",
        boxShadow: "0 4px 14px color-mix(in srgb, var(--text) 18%, transparent)",
      }}
      data-testid={like ? "partner-like" : "partner-pass"}
    >
      <PartnerIcon name={like ? "check" : "close"} size={28} strokeWidth={2.5} />
    </button>
  );
}

function Empty({ title, text, children }: { title: string; text: string; children?: ReactNode }) {
  return (
    <div className="mt-6 flex flex-col items-center gap-2 rounded-3xl px-4 py-10 text-center" style={{ background: "var(--panel-muted)" }} data-testid="partner-deck-empty">
      <h2 className="text-lg font-extrabold" style={{ color: "var(--text)" }}>{title}</h2>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{text}</p>
      {children}
    </div>
  );
}

function TextButton({ onClick, children }: { onClick: () => void; children: string }) {
  return (
    <button type="button" onClick={onClick} className="min-h-11 text-sm font-semibold" style={{ color: "var(--primary)" }}>
      {children}
    </button>
  );
}

/** «Φίλτρα»: the shared full-screen filter page, one section per filter. */
function DeckFilters({
  overview,
  filter,
  onChange,
  onClear,
  onClose,
}: {
  overview: PartnersOverview;
  filter: PartnerDeckFilter;
  onChange: (next: PartnerDeckFilter) => void;
  onClear: () => void;
  onClose: () => void;
}) {
  const t = useTranslations("Partners");
  const tFilters = useTranslations("Filters");
  const tags = useTranslations("BoxTags");
  const { options } = overview;
  const one = (key: keyof PartnerDeckFilter, label: string, values: readonly string[], text: (value: string) => string) =>
    values.length > 1 ? (
      <FilterSection key={key} label={label}>
        <ChoiceChips
          ariaLabel={label}
          multiple={false}
          options={[{ value: ALL, label: tFilters("all") }, ...values.map((value) => ({ value, label: text(value) }))]}
          selected={filter[key].length > 0 ? filter[key] : [ALL]}
          onChange={([value]) => onChange({ ...filter, [key]: value === ALL ? [] : [value] })}
        />
      </FilterSection>
    ) : null;
  const km = filter.within[0] && options.distances_km.includes(Number(filter.within[0])) ? filter.within[0] : String(options.default_within_km);
  return (
    <FilterPage title={t("filters")} onClose={onClose} onClear={onClear}>
      {overview.distance === "available" ? (
        <FilterSection label={t("distanceLabel")}>
          <ChoiceChips
            ariaLabel={t("distanceLabel")}
            multiple={false}
            options={options.distances_km.map((value) => ({ value: String(value), label: t("withinKm", { km: value }) }))}
            selected={[km]}
            onChange={([value]) => onChange({ ...filter, within: [value] })}
          />
        </FilterSection>
      ) : null}
      {one("time", t("timesLabelShort"), options.times, (value) => t(`time_${value}`))}
      {one("level", t("levelLabel"), options.levels, (value) => t(`level_${value}`))}
      {one("goal", t("goalLabelShort"), options.goals, (value) => t(`goal_${value}`))}
      {one("discipline", t("disciplineLabel"), options.disciplines, (value) => tags(`discipline.${value}`))}
    </FilterPage>
  );
}

/** «Βρήκατε συναθλητή»: you both said yes. */
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
