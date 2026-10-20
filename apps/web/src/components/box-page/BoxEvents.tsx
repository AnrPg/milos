"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { boxEventsKey, fetchBoxEvents } from "@/api/events";
import { EventList } from "@/components/events/EventParts";

import { EmptyTab } from "./BoxPosts";

/** «Events»: the box's upcoming events open to everyone; anyone signed in says «Θα έρθω» (board 8 Q4). */
export function BoxEvents({ slug, token }: { slug: string; token: string }) {
  const t = useTranslations("BoxPage");
  const events = useQuery({ queryKey: boxEventsKey(slug), queryFn: () => fetchBoxEvents(token, slug) });

  if (events.isPending) return <p className="py-6 text-center text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (!events.data || events.data.length === 0) return <EmptyTab text={t("eventsEmpty")} />;
  return (
    <div className="rounded-3xl px-4 py-1" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <EventList events={events.data} />
    </div>
  );
}
