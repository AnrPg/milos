"use client";

import { useLocale, useTranslations } from "next-intl";

import type { OpeningHoursSpan } from "@/api/facility";
import { TimeInput } from "@/components/ui/DateInput";

const WEEKDAYS = [1, 2, 3, 4, 5, 6, 7];
const WORKDAYS = [2, 3, 4, 5];
// 2024-01-01 was a Monday; used only to name weekdays in the viewer's language.
const weekdayName = (locale: string, weekday: number) =>
  new Intl.DateTimeFormat(locale, { weekday: "long", timeZone: "UTC" }).format(Date.UTC(2024, 0, weekday));

const fieldStyle = { background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" };

/**
 * The day's spans after «+»: a closed day opens 07:00–22:00; an open day gets
 * a midday break, its last span split around 13:00–16:00 when it allows.
 */
function withAddedSpan(spans: OpeningHoursSpan[], weekday: number): OpeningHoursSpan[] {
  const last = spans.at(-1);
  if (!last) return [{ weekday, opens: "07:00", closes: "22:00" }];
  if (last.opens < "13:00" && last.closes > "16:00")
    return [...spans.slice(0, -1), { ...last, closes: "13:00" }, { weekday, opens: "16:00", closes: last.closes }];
  return [...spans, { weekday, opens: last.closes, closes: last.closes < "23:00" ? "23:00" : "23:59" }];
}

/**
 * A row per weekday with one or more spans (plan §5a, board 3 Q4) and a
 * shortcut that copies Monday to the other weekdays.
 */
export function OpeningHoursEditor({
  value,
  onChange,
}: {
  value: OpeningHoursSpan[];
  onChange: (spans: OpeningHoursSpan[]) => void;
}) {
  const t = useTranslations("AdminLocation");
  const locale = useLocale();
  const byDay = (weekday: number) => value.filter((span) => span.weekday === weekday);
  const replaceDay = (weekday: number, spans: OpeningHoursSpan[]) =>
    onChange(
      [...value.filter((span) => span.weekday !== weekday), ...spans].sort(
        (a, b) => a.weekday - b.weekday || a.opens.localeCompare(b.opens),
      ),
    );
  const monday = byDay(1);

  return (
    <div className="flex flex-col gap-2">
      {WEEKDAYS.map((weekday) => {
        const spans = byDay(weekday);
        const name = weekdayName(locale, weekday);
        return (
          <div
            key={weekday}
            className="grid gap-2 rounded-2xl px-3 py-2.5 sm:grid-cols-[7rem_1fr] sm:items-start sm:gap-3"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
          >
            <span className="text-sm font-semibold capitalize sm:pt-2" style={{ color: "var(--text)" }}>
              {name}
            </span>
            <div className="flex flex-wrap items-center gap-2">
              {spans.length === 0 ? (
                <span className="text-sm" style={{ color: "var(--dim)" }}>
                  {t("closed")}
                </span>
              ) : null}
              {spans.map((span, index) => (
                <span key={index} className="flex items-center gap-1">
                  <TimeInput
                    aria-label={t("opensAt", { day: name })}
                    value={span.opens}
                    onValueChange={(value) =>
                      replaceDay(
                        weekday,
                        spans.map((other, at) => (at === index ? { ...other, opens: value } : other)),
                      )
                    }
                    className="w-[8rem] rounded-xl px-2 py-1.5 font-mono text-sm"
                    style={fieldStyle}
                  />
                  <span aria-hidden="true" style={{ color: "var(--dim)" }}>
                    –
                  </span>
                  <TimeInput
                    aria-label={t("closesAt", { day: name })}
                    value={span.closes}
                    onValueChange={(value) =>
                      replaceDay(
                        weekday,
                        spans.map((other, at) => (at === index ? { ...other, closes: value } : other)),
                      )
                    }
                    className="w-[8rem] rounded-xl px-2 py-1.5 font-mono text-sm"
                    style={fieldStyle}
                  />
                  <button
                    type="button"
                    aria-label={t("removeSpan", { day: name })}
                    onClick={() => replaceDay(weekday, spans.filter((_, at) => at !== index))}
                    className="grid h-8 w-8 place-items-center rounded-full"
                    style={{ color: "var(--dim)" }}
                  >
                    <span aria-hidden="true">✕</span>
                  </button>
                </span>
              ))}
              <button
                type="button"
                aria-label={t("addSpan", { day: name })}
                onClick={() => replaceDay(weekday, withAddedSpan(spans, weekday))}
                className="grid h-8 w-8 place-items-center rounded-full text-lg font-bold"
                style={{ color: "var(--primary)", border: "1px solid var(--border)" }}
              >
                <span aria-hidden="true">+</span>
              </button>
            </div>
          </div>
        );
      })}
      <button
        type="button"
        disabled={monday.length === 0}
        onClick={() =>
          onChange(
            [
              ...value.filter((span) => !WORKDAYS.includes(span.weekday)),
              ...WORKDAYS.flatMap((weekday) => monday.map((span) => ({ ...span, weekday }))),
            ].sort((a, b) => a.weekday - b.weekday || a.opens.localeCompare(b.opens)),
          )
        }
        className="self-start text-sm font-semibold disabled:opacity-40"
        style={{ color: "var(--primary)" }}
      >
        {t("copyMonday")}
      </button>
    </div>
  );
}
