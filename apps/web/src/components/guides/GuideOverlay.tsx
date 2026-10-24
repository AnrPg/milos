"use client";

import { useCallback, useEffect, useLayoutEffect, useRef, useState, type CSSProperties } from "react";
import { createPortal } from "react-dom";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { ADMIN_BUSINESS_KEY, seedDemoData } from "@/api/business-accounts";
import { useSession } from "@/components/session-provider";
import { DialogButton } from "@/components/ui/Dialog";
import { findAnchor, type GuideAnchor } from "@/lib/guides/anchors";
import { onRoute, resolveRoute, routeHref, stepCopyKey } from "@/lib/guides/engine";
import { cardPlacement, scrimPath, spotlightRect, type CardPlacement } from "@/lib/guides/placement";
import type { Guide, GuideStep } from "@/lib/guides/types";
import { useOrganizationSlug } from "@/lib/organization-slug";

import { placementClass, placementStyle } from "./card-layout";
import { useOptionalGuides } from "./GuideProvider";

/** How long a step looks for its spot (a page loading, an editor opening). */
const SEEK_MS = 2500;
/** How long «Next» on a step with an action waits for the screen it opens. */
const ACTION_MS = 2000;
const POLL_MS = 120;

type Rect = { left: number; top: number; right: number; bottom: number; width: number; height: number };

/**
 * ADR-193: the running walkthrough over the real screen. The step's spot is
 * cut out of a dimmed layer and ringed; everything else is dimmed and does
 * not react, so the next move is obvious. A step with an action pulses its
 * spot and moves on once the person did it (or «Next» does it for them). A
 * step whose spot is not on screen explains itself in the middle instead.
 * The layer sits on --z-tour: over dialogs and drawers, under their menus.
 */
export function GuideOverlay() {
  const guides = useOptionalGuides();
  // Which way the person is going, so a step left out skips the right way.
  const direction = useRef<1 | -1>(1);
  if (!guides?.active || typeof document === "undefined") return null;
  const { guide, steps, index } = guides.active;
  return (
    <ActiveStep
      key={`${guide.id}:${index}`}
      guide={guide}
      step={steps[index]}
      index={index}
      total={steps.length}
      direction={direction}
      onGo={(next) => {
        direction.current = next < index ? -1 : 1;
        if (next >= steps.length) guides.finish();
        else guides.goTo(next);
      }}
      onClose={() => (index === steps.length - 1 ? guides.finish() : guides.dismiss())}
      routeParams={guides.routeParams}
      demo={guides.abilities.demo && guides.abilities.manager}
    />
  );
}

function ActiveStep({
  guide,
  step,
  index,
  total,
  direction,
  onGo,
  onClose,
  routeParams,
  demo,
}: {
  guide: Guide;
  step: GuideStep;
  index: number;
  total: number;
  direction: { current: 1 | -1 };
  onGo: (index: number) => void;
  onClose: () => void;
  routeParams: { gymClub?: string | null };
  demo: boolean;
}) {
  const t = useTranslations("Guides");
  const tAll = useTranslations();
  const router = useRouter();
  const pathname = usePathname() ?? "/";
  const searchParams = useSearchParams();
  const organizationSlug = useOrganizationSlug();
  const cardRef = useRef<HTMLDivElement>(null);
  const headingRef = useRef<HTMLHeadingElement>(null);
  const [rect, setRect] = useState<Rect | null>(null);
  const [missing, setMissing] = useState(!step.anchor);
  const [cardSize, setCardSize] = useState({ width: 360, height: 220 });
  const [viewport, setViewport] = useState(() => ({ width: window.innerWidth, height: window.innerHeight }));
  const [busy, setBusy] = useState(false);
  const [nudge, setNudge] = useState(0);
  const last = index === total - 1;

  const route = step.route ? resolveRoute(step.route, routeParams) : null;
  const unreachable = Boolean(step.route && !route);
  const onStepRoute = !route || onRoute(route, pathname, searchParams.toString());

  // 1. The step's page.
  const navigated = useRef(false);
  useEffect(() => {
    if (!route || onStepRoute || navigated.current) return;
    navigated.current = true;
    router.push(routeHref(route, organizationSlug));
  }, [onStepRoute, organizationSlug, route, router]);

  // 2. Its spot, followed while the page scrolls, resizes or re-renders.
  useEffect(() => {
    if (!step.anchor || !onStepRoute || unreachable) return;
    const anchor = step.anchor;
    const startedAt = performance.now();
    let frame = 0;
    let scrolled = false;
    let lost = false;
    const tick = () => {
      const element = findAnchor(anchor);
      if (element) {
        if (!scrolled) {
          scrolled = true;
          revealElement(element);
        }
        const box = element.getBoundingClientRect();
        setRect((current) => (sameRect(current, box) ? current : toRect(box)));
        setMissing(false);
      } else if (!lost && performance.now() - startedAt > SEEK_MS) {
        lost = true;
        setRect(null);
        setMissing(true);
      }
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [onStepRoute, step.anchor, unreachable]);

  const stepMissing = unreachable || (Boolean(step.anchor) && missing);
  // A step that may be left out goes on the way the person was going.
  useEffect(() => {
    if (stepMissing && step.missing === "skip") onGo(index + direction.current);
  }, [direction, index, onGo, step.missing, stepMissing]);

  // 3. Its action: the step moves on once the person did it.
  const done = useRef(false);
  const advance = useCallback(() => {
    if (done.current) return;
    done.current = true;
    onGo(index + 1);
  }, [index, onGo]);
  useEffect(() => {
    const action = step.action;
    if (!action || stepMissing) return;
    let tapped = false;
    const onClick = (event: MouseEvent) => {
      const target = findAnchor(action.target);
      if (target && event.target instanceof Node && target.contains(event.target)) tapped = true;
    };
    document.addEventListener("click", onClick, true);
    const timer = window.setInterval(() => {
      if (reached(action)) advance();
      else if (tapped && !action.until && !action.untilGone) advance();
    }, POLL_MS);
    return () => {
      document.removeEventListener("click", onClick, true);
      window.clearInterval(timer);
    };
  }, [advance, step.action, stepMissing]);

  // The card follows its content's size and the screen's.
  useLayoutEffect(() => {
    const card = cardRef.current;
    if (!card) return;
    const measure = () => {
      setCardSize((current) =>
        current.width === card.offsetWidth && current.height === card.offsetHeight ? current : { width: card.offsetWidth, height: card.offsetHeight },
      );
      setViewport((current) =>
        current.width === window.innerWidth && current.height === window.innerHeight ? current : { width: window.innerWidth, height: window.innerHeight },
      );
    };
    measure();
    const observer = typeof ResizeObserver === "undefined" ? null : new ResizeObserver(measure);
    observer?.observe(card);
    window.addEventListener("resize", measure);
    return () => {
      observer?.disconnect();
      window.removeEventListener("resize", measure);
    };
  }, []);

  // Each step starts with its title, for keyboards and screen readers.
  useEffect(() => {
    headingRef.current?.focus({ preventScroll: true });
  }, []);

  async function next() {
    if (busy) return;
    if (last) {
      onGo(total);
      return;
    }
    const action = step.action;
    if (action && !stepMissing) {
      setBusy(true);
      findAnchor(action.target)?.click();
      if (action.until || action.untilGone) await waitFor(() => reached(action), ACTION_MS);
      advance();
      return;
    }
    if (step.leave) {
      const leave = findAnchor(step.leave);
      if (leave) {
        leave.click();
        await waitFor(() => !findAnchor(step.leave!), ACTION_MS);
      }
    }
    advance();
  }

  function back() {
    if (index > 0) onGo(index - 1);
  }

  // Keys: Escape closes, the arrows move while the card has focus.
  const nextRef = useRef(next);
  const backRef = useRef(back);
  const closeRef = useRef(onClose);
  useEffect(() => {
    nextRef.current = next;
    backRef.current = back;
    closeRef.current = onClose;
  });
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        // Caught before an open dialog sees it: Escape ends the guide, not the dialog under it.
        event.stopPropagation();
        event.preventDefault();
        closeRef.current();
        return;
      }
      if (!cardRef.current?.contains(document.activeElement)) return;
      const rtl = getComputedStyle(cardRef.current).direction === "rtl";
      if (event.key === (rtl ? "ArrowLeft" : "ArrowRight")) void nextRef.current();
      if (event.key === (rtl ? "ArrowRight" : "ArrowLeft")) backRef.current();
    };
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, []);

  const rtl = typeof document !== "undefined" && document.dir === "rtl";
  const spot = rect && !stepMissing ? spotlightRect(rect, viewport) : null;
  const placement: CardPlacement = cardPlacement(spot ? { ...spot, right: spot.left + spot.width, bottom: spot.top + spot.height } : null, cardSize, viewport, rtl);
  const seeking = Boolean(step.anchor) && !spot && !stepMissing;
  const labels = Object.fromEntries(
    Object.entries(step.labels ?? {}).map(([name, path]) => [name, (tAll as unknown as (key: string) => string)(path).replace(/^\+\s*/, "").trim()]),
  );
  // Guide copy is keyed by the registry's ids, so it is looked up untyped.
  const copy = t as unknown as (key: string, values?: Record<string, string>) => string;
  const title = copy(stepCopyKey(guide.id, step.id, "title"), labels);
  const body = copy(stepCopyKey(guide.id, step.id, "body"), labels);
  const tip = step.tip ? copy(stepCopyKey(guide.id, step.id, "tip"), labels) : null;
  const chapter = step.chapter ? copy(stepCopyKey(guide.id, "chapters", step.chapter)) : null;
  const acting = Boolean(step.action) && !stepMissing;

  return createPortal(
    <>
      <Scrim spot={spot} viewport={viewport} onPress={() => setNudge((value) => value + 1)} />
      {spot ? (
        <div
          aria-hidden="true"
          className={`guide-move pointer-events-none fixed rounded-2xl z-(--z-tour) ${acting ? "guide-pulse" : ""}`}
          style={{ left: spot.left, top: spot.top, width: spot.width, height: spot.height, border: "2px solid var(--primary)" }}
        />
      ) : null}
      <div
        ref={cardRef}
        role="dialog"
        aria-modal="false"
        aria-labelledby="guide-card-title"
        aria-describedby="guide-card-body"
        data-testid="guide-card"
        data-guide-step={`${guide.id}.${step.id}`}
        className={`fixed flex flex-col gap-3 p-4 shadow-lg z-(--z-tour) ${placementClass(placement)} ${nudge ? "guide-pulse" : ""}`}
        style={{
          ...placementStyle(placement),
          background: "var(--panel)",
          border: "1px solid var(--border)",
          color: "var(--text)",
          visibility: seeking ? "hidden" : undefined,
        }}
        onAnimationEnd={() => setNudge(0)}
      >
        <div className="flex items-center gap-2">
          <p className="min-w-0 flex-1 truncate text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--dim)" }}>
            {chapter ? `${chapter} · ` : ""}
            {t("ui.stepOf", { current: index + 1, total })}
          </p>
          <button
            type="button"
            onClick={onClose}
            aria-label={t("ui.close")}
            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-lg"
            style={{ color: "var(--dim)" }}
          >
            ×
          </button>
        </div>
        <Progress index={index} total={total} />
        <div className="flex flex-col gap-1">
          <h2 id="guide-card-title" ref={headingRef} tabIndex={-1} className="text-lg font-semibold outline-none">
            {title}
          </h2>
          <p id="guide-card-body" className="text-sm" style={{ color: "var(--text-soft)" }} aria-live="polite">
            {body}
          </p>
          {acting ? (
            <p className="text-xs font-semibold" style={{ color: "var(--primary-strong, var(--primary))" }}>
              <span aria-hidden="true">☝ </span>
              {t("ui.tapHint")}
            </p>
          ) : null}
          {stepMissing && step.anchor ? (
            <p className="text-xs" style={{ color: "var(--dim)" }}>{t("ui.notHere")}</p>
          ) : null}
          {tip ? (
            <p className="mt-1 rounded-xl px-3 py-2 text-xs" style={{ background: "var(--panel-raised)", color: "var(--text-soft)" }}>
              <span aria-hidden="true">💡 </span>
              {tip}
            </p>
          ) : null}
        </div>
        {index === 0 && demo && guide.demoSection ? <DemoFill section={guide.demoSection} /> : null}
        <div className="flex gap-2">
          {index > 0 ? (
            <DialogButton tone="ghost" onClick={back} className="flex-1">
              {t("ui.back")}
            </DialogButton>
          ) : null}
          <DialogButton tone="primary" onClick={() => void next()} disabled={busy} className="flex-1" testId="guide-next">
            {last ? t("ui.finish") : acting ? t("ui.doIt") : t("ui.next")}
          </DialogButton>
        </div>
      </div>
    </>,
    document.body,
  );
}

/** Everything but the spot is dimmed and ignores presses; a press there nudges the card. */
function Scrim({ spot, viewport, onPress }: { spot: { left: number; top: number; width: number; height: number } | null; viewport: { width: number; height: number }; onPress: () => void }) {
  const { width, height } = viewport;
  const path = scrimPath(viewport, spot);
  return (
    <svg
      aria-hidden="true"
      className="pointer-events-none fixed inset-0 z-(--z-tour)"
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
    >
      <path
        d={path}
        fillRule="evenodd"
        style={{ fill: "var(--scrim)", pointerEvents: "auto" } as CSSProperties}
        onClick={onPress}
      />
    </svg>
  );
}

function Progress({ index, total }: { index: number; total: number }) {
  return (
    <div aria-hidden="true" className="grid gap-1" style={{ gridTemplateColumns: `repeat(${total}, minmax(0, 1fr))` }}>
      {Array.from({ length: total }, (_, position) => (
        <span
          key={position}
          className="h-1 rounded-full"
          style={{ background: position <= index ? "var(--primary)" : "var(--border)" }}
        />
      ))}
    </div>
  );
}

/** ADR-184: a business in demo mode can fill the screens first, so the guide has something to show. */
function DemoFill({ section }: { section: NonNullable<Guide["demoSection"]> }) {
  const t = useTranslations("Guides");
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const seed = useMutation({
    mutationFn: () => seedDemoData(tokens!.access_token, section),
    onSuccess: (status) => {
      queryClient.setQueriesData({ queryKey: ADMIN_BUSINESS_KEY }, status);
      void queryClient.invalidateQueries();
    },
  });
  if (!tokens?.access_token) return null;
  return seed.isSuccess ? (
    <p role="status" className="text-xs font-semibold" style={{ color: "var(--success)" }}>{t("ui.demoFilled")}</p>
  ) : (
    <DialogButton onClick={() => seed.mutate()} disabled={seed.isPending}>
      {seed.isPending ? t("ui.filling") : t("ui.fillDemo")}
    </DialogButton>
  );
}

function reached(action: { until?: GuideAnchor; untilGone?: GuideAnchor }) {
  if (action.until && !findAnchor(action.until)) return false;
  if (action.untilGone && findAnchor(action.untilGone)) return false;
  return Boolean(action.until || action.untilGone);
}

function waitFor(check: () => boolean, timeout: number) {
  return new Promise<void>((resolve) => {
    const startedAt = performance.now();
    const timer = window.setInterval(() => {
      if (check() || performance.now() - startedAt > timeout) {
        window.clearInterval(timer);
        resolve();
      }
    }, POLL_MS);
  });
}

/** Brings the spot on screen, without moving a page that already shows it. */
function revealElement(element: HTMLElement) {
  const box = element.getBoundingClientRect();
  const fits = box.top >= 0 && box.bottom <= window.innerHeight;
  if (fits) return;
  const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
  element.scrollIntoView({ block: box.height > window.innerHeight * 0.7 ? "start" : "center", inline: "nearest", behavior: reduce ? "auto" : "smooth" });
}

function toRect(box: DOMRect): Rect {
  return { left: box.left, top: box.top, right: box.right, bottom: box.bottom, width: box.width, height: box.height };
}

function sameRect(current: Rect | null, box: DOMRect) {
  return Boolean(
    current &&
      Math.abs(current.left - box.left) < 0.5 &&
      Math.abs(current.top - box.top) < 0.5 &&
      Math.abs(current.width - box.width) < 0.5 &&
      Math.abs(current.height - box.height) < 0.5,
  );
}
