"use client";

import { useState } from "react";

import type { TrainingQuote } from "@/api/landing";
import { useUiTranslations } from "@/i18n/ui";

/**
 * Αρχική's opening card: a time-of-day greeting and the gym's quote of the
 * day. Streak and badges live in Ημερολόγιο › Πρόοδος (ADR-137).
 */
export function GreetingCard({ nickname, quote }: { nickname: string; quote: TrainingQuote | null | undefined }) {
  const i18n = useUiTranslations();

  const [greeting] = useState(() => {
    const h = new Date().getHours();
    const morning = [
      i18n("riseAndGrind3033458") + " " + nickname + i18n("orJustRiseGrindIsOptional8d8c3f6"),
      i18n("theBarbellsMissedYoub43c56d") + " " + nickname + ".",
      i18n("coffeeFirstPrsSecond69f0009") + " " + nickname + i18n("youKnowTheOrderaa2bad9"),
      i18n("theGymCalledItSaidWhereWereYouef08f7d") + " " + nickname + ".",
      i18n("earlyBirdGetsTheGains77f123b") + " " + nickname + i18n("youReAlreadyWinninge6c3cef"),
      i18n("theSunIsUpTheWeightsAreWaiting171ab2a") + " " + nickname + ".",
    ];
    const afternoon = [
      i18n("afternoonSlumpNotOnYourWatchb7a458d") + " " + nickname + ".",
      i18n("lunchWasJustPreWorkout0bddce3") + " " + nickname + i18n("youKnowThatRightf5b4ce7"),
      i18n("halfwayThroughTheDayAndStillGoingStronge7ef8ba") + " " + nickname + ".",
      i18n("theAfternoonBelongsToThoseWhoShowUpfa22611") + " " + nickname + ".",
      i18n("peakPerformanceHoursadbdea7") + " " + nickname + i18n("letSNotWasteThem2bbfea8"),
      i18n("yourFutureSelfWillThankYouForThisb9d7f03") + " " + nickname + ".",
    ];
    const evening = [
      i18n("oneMoreWorkoutBetweenYouAndTheCouch785f7b7") + " " + nickname + ".",
      i18n("trainNowSleepLikeAChampionLater15d2672") + " " + nickname + ".",
      i18n("theDayIsnTOverUntilYouMove57cf5fe") + " " + nickname + ".",
      i18n("eveningEdition5696108") + " " + nickname + i18n("theWeightsAreStillWarm7b8a706"),
      i18n("theBestTimeWasThisMorningTheSecondbc0aef8") + " " + nickname + ".",
      i18n("dedicationLooksGoodOnYou7e7964f") + " " + nickname + ".",
    ];
    const night = [
      i18n("aTrueChampion483d1f4") + " " + nickname + i18n("orAnInsomniacEitherWayLetSGo18a41d1"),
      i18n("everyoneElseIsAsleep3996bf0") + " " + nickname + i18n("thisIsYourMomentce39f71"),
      i18n("nightOwlModeActivatedc6ea0aa") + " " + nickname + i18n("theWeightsDonTJudge5c9cfe5"),
      i18n("canTSleepMightAsWellGetStronger928dcf6") + " " + nickname + ".",
      i18n("midnightHustle3333fcf") + " " + nickname + i18n("respectbf97b93"),
      i18n("theIronNeverSleepsba0aebe") + " " + nickname + i18n("neitherDoYouApparentlyb95a33c"),
    ];
    const pool =
      h >= 5 && h < 12 ? morning :
      h >= 12 && h < 18 ? afternoon :
      h >= 18 && h < 22 ? evening :
      night;
    return pool[Math.floor(Math.random() * pool.length)]!;
  });

  return (
    <section className="rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <style>{`
        @keyframes quote-border-glow {
          0%, 100% {
            border-color: color-mix(in srgb, var(--primary) 22%, transparent);
            box-shadow: 0 0 0 0 color-mix(in srgb, var(--primary) 0%, transparent);
          }
          50% {
            border-color: color-mix(in srgb, var(--primary) 65%, transparent);
            box-shadow: 0 0 18px 3px color-mix(in srgb, var(--primary) 15%, transparent);
          }
        }
      `}</style>

      {/* Welcome */}
      <p className="text-sm font-semibold" style={{ color: "var(--muted)" }}>
        {greeting}
      </p>

      {/* Quote */}
      <blockquote
        className="mt-4 rounded-2xl px-5 py-4"
        style={{
          border: "1.5px solid color-mix(in srgb, var(--primary) 22%, transparent)",
          animation: "quote-border-glow 3s ease-in-out infinite",
        }}
      >
        <p
          className="text-3xl font-bold leading-snug tracking-tight md:text-4xl"
          style={{ color: "var(--primary)", fontStyle: "italic" }}
        >
          {quote?.body ?? i18n("yourTrainingIsInMotioncfd94f0")}
        </p>
        {quote?.author ? (
          <footer className="mt-2 text-sm" style={{ color: "var(--dim)" }}>— {quote.author}</footer>
        ) : null}
      </blockquote>
    </section>
  );
}
